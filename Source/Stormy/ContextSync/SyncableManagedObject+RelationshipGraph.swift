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
        static private var current: RelationshipGraph!
        static var currentGraph: RelationshipGraph {
            if let cur = current { return cur }
            
            current = RelationshipGraph()
            return current
        }
        
		  var isSyncInProgress = false
		  var resyncAtEnd = false
        var startTimer: Timer?
        func add(graph: RelationshipGraph) {
            consideredObjects += graph.consideredObjects
        }
        
        func add(completion: ((Error?) -> Void)? = nil) {
            guard let completion = completion else { return }
            completions.append(completion)
        }
        
        func callCompletions(with error: Error?) {
			  print("Completing Sync")
			  let complete: [(Error?) -> Void] = completions
			  completions = []
			  resyncAtEnd = false
			  isSyncInProgress = false
			  complete.forEach { $0(error) }
        }
        
        func queue(completion: ((Error?) -> Void)? = nil) {
			  if isSyncInProgress {
				  resyncAtEnd = true
				  return
			  }
			  isSyncInProgress = true
            if self !== Self.current {
                print("Queuing \(consideredObjects.count) objects")
                Self.currentGraph.add(graph: self)
                Self.currentGraph.add(completion: completion)
                Self.currentGraph.queue()
                return
            }
            startTimer?.invalidate()
            DispatchQueue.main.async {
					print("Retting timer")
                self.startTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
						 print("Staring sync")
                    self.sync()
                }
            }
        }
        
		var consideredObjects: [SyncableManagedObject] = []
		var managedObjectContext: NSManagedObjectContext? { return self.consideredObjects.first?.managedObjectContext }
		var scope: CKDatabase.Scope
        var completions: [(Error?) -> Void] = []
		
		init(scope: CKDatabase.Scope = .private) {
			self.scope = scope
		}

		func append(_ object: SyncableManagedObject) {
			if !self.consideredObjects.contains(object) { self.consideredObjects.append(object) }
		}
		
		func prune() {
            var saved: [SyncableManagedObject] = []
            
            for object in consideredObjects {
                if !saved.contains(object), object.syncState == .dirty {
                    saved.append(object)
                }
            }
            
            self.consideredObjects = saved
        }
		
		var count: Int { return self.consideredObjects.count }
		
		func sync(completion: ((Error?) -> Void)? = nil) {
			print("Starting sync")
			add(completion: completion)

			self.prune()
				if self.consideredObjects.isEmpty { callCompletions(with: nil); return }
            print("Syncing \(consideredObjects.count) objects")
            if self === Self.current { Self.current = nil }
			guard let context = self.managedObjectContext, !SyncedContainer.mutability.isReadOnlyForCloudOps else {
                callCompletions(with: nil)
				return
			}

			let recordIDs = self.consideredObjects.map { $0.recordID }
			
			self.consideredObjects.forEach { SyncedContainer.instance.markRecordID($0.recordID, inProgress: true) }
			Stormy.instance.fetch(ids: recordIDs, in: self.scope) { cachedResults, error in
				print("Saving \(cachedResults.count)")
				context.perform {
					var saved: [CKRecord] = []
					
					for record in self.consideredObjects {
						if let cache = cachedResults[record.recordID] {
							record.load(into: cache)
                            if let updated = cache.updatedRecord(using: record) { saved.append(updated) }
						} else {
                            if let updated = record.localCache.updatedRecord(using: record) { saved.append(updated) }
						}
					}
					
					let op = CKModifyRecordsOperation(recordsToSave: saved, recordIDsToDelete: nil)
					print("Saving \(saved.map { $0.recordID })")
					op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
						if let nsError = (error as? NSError), nsError.code == 2, nsError.domain == CKErrorDomain, let underlying = nsError.userInfo["NSUnderlyingError"] as? NSError {
							
							print(underlying)
						}
                        if Stormy.shouldReturn(after: error, operation: op, in: self.scope, completion: { err in self.callCompletions(with: err) }) {
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
                            self.callCompletions(with: nil)
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
