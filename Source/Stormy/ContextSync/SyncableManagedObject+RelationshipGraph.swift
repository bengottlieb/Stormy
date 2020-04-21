//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 4/15/20.
//

import Foundation
import CloudKit
import CoreData


extension SyncableManagedObject {
	class RelationshipGraph {
		var consideredObjects: [SyncableManagedObject] = []
		var managedObjectContext: NSManagedObjectContext? { return self.consideredObjects.first?.managedObjectContext }
		var scope: CKDatabase.Scope
		
		init(scope: CKDatabase.Scope = .private) {
			self.scope = scope
		}

		func append(_ object: SyncableManagedObject) {
			if !self.consideredObjects.contains(object) { self.consideredObjects.append(object) }
		}
		
		func prune() {
			self.consideredObjects = self.consideredObjects.filter { $0.syncState == .dirty }
		}
		
		var count: Int { return self.consideredObjects.count }
		
		func sync(completion: ((Error?) -> Void)?) {
			guard let context = self.managedObjectContext else {
				completion?(nil)
				return
			}

			let recordIDs = self.consideredObjects.map { $0.recordID }
			
			self.consideredObjects.forEach { SyncedContainer.instance.markRecordID($0.recordID, inProgress: true) }
			Stormy.instance.fetch(ids: recordIDs, in: self.scope) { cachedResults, error in
				context.perform {
					var saved: [CKRecord] = []
					
					for record in self.consideredObjects {
						if let cache = cachedResults[record.recordID] {
							record.load(into: cache)
							if let updated = cache.updatedRecord() { saved.append(updated) }
						} else {
							if let updated = record.localCache.updatedRecord() { saved.append(updated) }
						}
					}
					
					let op = CKModifyRecordsOperation(recordsToSave: saved, recordIDsToDelete: nil)
					op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
						if Stormy.shouldReturn(after: error, operation: op, in: self.scope, completion: completion) {
							Stormy.instance.completeLongRunningTask()
							return
						}
						
						context.perform {
							for cache in cachedResults {
								if let record = self.consideredObjects[cache.recordID] {
									record.syncState = .upToDate
								}
							}
							do {
								try context.save()
							} catch {
								print("Error while saving the sync context: \(error)")
							}
							cachedResults.forEach { SyncedContainer.instance.markRecordID($0.recordID, inProgress: false) }
							completion?(nil)
						}

					}
					
					Stormy.instance.queue(operation: op, in: self.scope)
				}
			}
		}
	}

}

extension Array where Element == CKRecord {
	subscript(recordID: CKRecord.ID) -> CKRecord? {
		for record in self {
			if record.recordID == recordID { return record }
		}
		return nil
	}
}

extension Array where Element == SyncableManagedObject {
	subscript(recordID: CKRecord.ID) -> SyncableManagedObject? {
		for record in self {
			if record.recordID == recordID { return record }
		}
		return nil
	}
}

extension Array where Element == CKLocalCache {
	subscript(recordID: CKRecord.ID) -> CKLocalCache? {
		for record in self {
			if record.recordID == recordID { return record }
		}
		return nil
	}
}
