//
//  SyncedContainer+Resync.swift
//  ContextSync
//
//  Created by Ben Gottlieb on 11/13/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit
import CoreData

@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
extension SyncedContainer {
	public func syncRecords(with ids: [CKRecord.ID], in database: CKDatabase.Scope, completion: @escaping (Error?) -> Void) {
		let queue = DispatchQueue(label: "fetchGroup")
		var finalError: Error?
		let batchSize = 300
		var first = 0
		var fetchedRecords: [CKLocalCache] = []
		Stormy.instance.startLongRunningTask()

		while true {
			let last = min(ids.count, first + batchSize)
			if last <= first { break }
			let op = CKFetchRecordsOperation(recordIDs: Array(ids[first..<last]))
			
			first = last
			queue.suspend()
			op.perRecordCompletionBlock = { record, id, error in
				if let err = error {
					print("Error fetching record: \(err)")
					finalError = err
				}
				if let cache = database.cache.fetch(record: record) {
					self.performInBackground() { moc in
						let object = moc.object(ofType: cache.typeName, withID: cache.recordID)
						object.read(from: cache)
						fetchedRecords.append(cache)
						if moc.hasChanges { try? moc.save() }
					}
				}
			}
			
			op.fetchRecordsCompletionBlock = { records, error in
				self.performInBackground() { moc in
					for cached in fetchedRecords {
						if let object = moc.lookupObject(ofType: cached.typeName, withID: cached.recordID) {
                            let relationshipNames = type(of: object).parentRelationshipNames + type(of: object).pertinentRelationshipNames
							if relationshipNames.isEmpty { continue }
							for parentName in relationshipNames {
                                if let parent = cached.lookupObject(named: parentName, in: moc) {
									object.setValue(parent, forKey: parentName)
								}
							}
						}
					}
					if moc.hasChanges { try? moc.save() }
					queue.resume()
					Stormy.instance.completeLongRunningTask()
					print("Sync Complete")
				}
			}
			
			Stormy.instance.queue(operation: op, in: database)
		}
		
		queue.async {
			completion(finalError)
		}
	}
	
	public func syncAllRecords(for types: [String] = Array(SyncedContainer.instance.syncedObjects.keys), completion: @escaping (Error?) -> Void) {
		let queue = DispatchQueue(label: "syncAll")
		var finalError: Error?
		
		Stormy.instance.startLongRunningTask()
		for type in types {
			guard let typeInfo = self.syncedObjects[type] else { continue }
			queue.suspend()
			self.fetchAllIDs(forRecordType: type, in: typeInfo.database) { remoteIDs, error in
				if let err = error { finalError = err }
				
				self.performInBackground() { moc in
					let request = NSFetchRequest<SyncableManagedObject>(entityName: type)
					
					if let records = try? request.execute() {
						let localIDs = records.map { $0.recordID }
						var missing: [CKRecord.ID] = []
						var deleted: [CKRecord.ID] = []
						
						for id in remoteIDs {
							if !localIDs.contains(id) { missing.append(id) }
						}
						
						for record in records {
							if !remoteIDs.contains(record.recordID) {
								deleted.append(record.recordID)
								moc.delete(record)
							}
						}
						
						if moc.hasChanges {
							do {
								try moc.save()
							} catch {
								finalError = error
							}
						}
						
						self.syncRecords(with: missing, in: typeInfo.database) { error in
							queue.resume()
						}
					} else {
						queue.resume()
					}
				}
			}
		}
		
		queue.async {
			completion(finalError)
			Stormy.instance.completeLongRunningTask()
		}
	}
	
	func fetchAllIDs(forRecordType type: String, in database: CKDatabase.Scope, completion: @escaping ([CKRecord.ID], Error?) -> Void) {
		self.fetchIDs(forRecordType: type, in: database, continuing: nil, currentIDs: [], completion: completion)
	}
	
	func fetchIDs(forRecordType type: String, in database: CKDatabase.Scope, continuing cursor: CKQueryOperation.Cursor?, currentIDs: [CKRecord.ID], completion: @escaping ([CKRecord.ID], Error?) -> Void) {
		let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
		let op = cursor == nil ? CKQueryOperation(query: query) : CKQueryOperation(cursor: cursor!)
		var ids: [CKRecord.ID] = currentIDs
		
		if cursor == nil { Stormy.instance.startLongRunningTask() }
		op.desiredKeys = []
		op.recordFetchedBlock = { record in
			ids.append(record.recordID)
		}
		
		op.queryCompletionBlock = { cursor, error in
			if let curs = cursor, error == nil {
				self.fetchIDs(forRecordType: type, in: database, continuing: curs, currentIDs: ids, completion: completion)
			} else {
				completion(ids, error)
				Stormy.instance.startLongRunningTask()
			}
		}
		
		Stormy.instance.queue(operation: op, in: database)
	}
	

}
