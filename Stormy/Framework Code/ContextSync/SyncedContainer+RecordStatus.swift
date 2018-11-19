//
//  SyncedContainer+RecordStatus.swift
//  ContextSync
//
//  Created by Ben Gottlieb on 11/5/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

@available(iOSApplicationExtension 10.0, *)
@available(OSXApplicationExtension 10.12, *)
extension CKRecord.ID {
	var databaseType: DatabaseType? {
		guard let name = self.typeName else { return nil }
		return SyncedContainer.instance.syncedObjects[name]?.database
	}
	
	convenience init?(unsyncedRecordName: String) {
		let id = CKRecord.ID(recordName: unsyncedRecordName)
		
		guard let entityName = id.typeName else {
			self.init(recordName: "")
			return nil
		}
		
		if let zoneName = SyncedContainer.instance.syncedObjects[entityName]?.zoneName {
			self.init(recordName: unsyncedRecordName, zoneID: Stormy.instance.zone(named: zoneName).zoneID)
		} else {
			self.init(recordName: unsyncedRecordName)
		}
	}
}

@available(iOSApplicationExtension 10.0, *)
@available(OSXApplicationExtension 10.12, *)
extension SyncedContainer {
	static let pendingRecordNamesKey = "syncPendingRecordNames"
	
	func checkForUnsyncedObjects() {
		self.container.performBackgroundTask { moc in
			let pending = self.syncPendingRecordNames
			for name in pending {
				if let id = CKRecord.ID(unsyncedRecordName: name) {
					guard let typeName = id.typeName, let db = self.syncedObjects[typeName]?.database else {
						self.markRecordID(id, inProgress: false)
						continue
					}
					let cache = db.cache.fetch(type: typeName, id: id)
					cache.object(in: moc)?.sync()
				}
			}
		}
	}
	
	var syncPendingRecordNames: [String] {
		get {
			return self.viewContext.persistentStoreCoordinator?.persistentStores.first?.metadata?[SyncedContainer.pendingRecordNamesKey] as? [String] ?? []
		}
		
		set {
			self.container.performBackgroundTask { moc in
				var metadata = moc.persistentStoreCoordinator?.persistentStores.first?.metadata ?? [:]
				
				metadata[SyncedContainer.pendingRecordNamesKey] = newValue
				self.viewContext.persistentStoreCoordinator?.persistentStores.first?.metadata = metadata
				try? moc.save()
			}
		}
	}
	
	func markRecordID(_ recordID: CKRecord.ID, inProgress: Bool) {
		var current = self.syncPendingRecordNames
		let id = recordID.recordName
		
		if inProgress {
			if current.contains(id) { return }
			current.append(id)
			self.syncPendingRecordNames = current
		} else if let index = current.index(of: id) {
			current.remove(at: index)
			self.syncPendingRecordNames = current
		}
	}
}
