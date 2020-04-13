//
//  SyncableManagedObject.swift
//  ContextSync
//
//  Created by Ben Gottlieb on 11/2/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CoreData
import CloudKit


@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
@objc open class SyncableManagedObject: NSManagedObject {
	public static var cloudKitRecordIDFieldName = "cloudKitRecordID_"		/// should be a string
	public static var syncStateFieldName = "cloudKitSyncState_"						/// should be an integer
	public static var devicePrefix = "device_"									/// fields prefixed with this will not be synced to iCloud

	open var cloudKitRecordType: String { return self.entity.name! }
	
	public var isSyncable: Bool {
		guard let id = self.primitiveValue(forKey: SyncableManagedObject.cloudKitRecordIDFieldName) as? String else { return false }
		return !id.isEmpty
	}
	open var uniqueID: String {
		get {
			let id = self.primitiveValue(forKey: SyncableManagedObject.cloudKitRecordIDFieldName) as? String
			if let realID = id, !realID.isEmpty { return realID }
			let newID = UUID().uuidString
			self.setPrimitiveValue(newID, forKey: SyncableManagedObject.cloudKitRecordIDFieldName)
			return newID
		}
		set { self.setPrimitiveValue(newValue, forKey: SyncableManagedObject.cloudKitRecordIDFieldName )}
	}
	
	open class func predicate(for id: CKRecord.ID) -> NSPredicate {
		return NSPredicate(format: "%K == %@", SyncableManagedObject.cloudKitRecordIDFieldName, id.recordID ?? id.recordName)
	}
	
	open class var parentRelationshipName: String? { return nil }
	
	open func willSync(withCache: CKLocalCache) {}
	
	open var localCache: CKLocalCache {
		let db = self.recordID.databaseType ?? SyncedContainer.instance.defaultDatabaseType
		let cache = db.cache.fetch(type: self.cloudKitRecordType, id: self.recordID)
		if !cache.isLoaded {
			self.load(into: cache)
		}
		return cache
	}
	
	override open func setValue(_ value: Any?, forKey key: String) {
		super.setValue(value, forKey: key)
	}
	
	open func isDeviceOnlyAttribute(_ attr: NSAttributeDescription) -> Bool { return attr.name.hasPrefix(SyncableManagedObject.devicePrefix) }

	open func read(from record: CKLocalCache) {
		for field in self.syncableFieldNames {
			let value = record[field]

			if let url = value as? URL {
				do {
					let data = try Data(contentsOf: url, options: [.mappedRead])
					self.setValue(data, forKey: field)
				} catch {
					print("Problem reading a \(field) from a temporary file: \(error)")
				}
			} else {
				self.setValue(value, forKey: field)
			}
		}
		self.uniqueID = record.recordID.recordID ?? record.recordID.recordName
		if let parent = record.parent { self.loadParent(from: parent) }
	}

	open func loadParent(from record: CKLocalCache) {
		guard let moc = self.managedObjectContext, let existing = record.object(in: moc) else { return }
		for (_, relationship) in self.entity.relationshipsByName {
			if relationship.destinationEntity == existing.entity, !relationship.isToMany  {
				self.setValue(existing, forKey: relationship.name)
			}
		}
	}
}


@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
extension SyncableManagedObject {
	var syncState: CKLocalCache.SyncState {
		get {
			let raw = self.value(forKey: SyncableManagedObject.syncStateFieldName) as? Int ?? 0
			return CKLocalCache.SyncState(rawValue: raw) ?? .upToDate
		}
		
		set {
			self.setValue(newValue.rawValue, forKey: SyncableManagedObject.syncStateFieldName)
		}
	}

	class RelationshipGraph {
		var consideredObjects: [SyncableManagedObject] = []
		
		func append(_ object: SyncableManagedObject) {
			self.consideredObjects.append(object)
		}

		func prune() {
			self.consideredObjects = self.consideredObjects.filter { $0.syncState == .dirty }
		}

		var count: Int { return self.consideredObjects.count }
	}

	public var recordID: CKRecord.ID {
		if let name = SyncedContainer.instance.zoneName(for: type(of: self)) {
			let zone = Stormy.instance.zone(named: name)
			return CKRecord.ID(recordName: self.uniqueID, typeName: self.entity.name!, zoneID: zone.zoneID)
		}
		return CKRecord.ID(recordName: self.uniqueID, typeName: self.entity.name!)
	}
	
	func connectCachedRelationships(withGraph graph: SyncableManagedObject.RelationshipGraph) {
		graph.append(self)
		
		if let parentName = Self.parentRelationshipName, let parent = self.value(forKey: parentName) as? SyncableManagedObject {
			self.localCache.setParent(parent.localCache)
		}
		
		for relationship in self.entity.relationshipsByName.values {
			guard let kids = self.value(forKey: relationship.name) as? Set<SyncableManagedObject>, let first = kids.first else { continue }
			
			if let parent = type(of: first).parentRelationshipName, first.entity.relationshipsByName[parent]?.destinationEntity?.managedObjectClassName == NSStringFromClass(type(of: self)) {
				kids.forEach { kid in kid.connectCachedRelationships(withGraph: graph) }
			}
		}
	}
	
	public func sync(completion: ((Error?) -> Void)? = nil) {
		let id = self.recordID
		SyncedContainer.instance.markRecordID(id, inProgress: true)
		self.syncState = .dirty
		((try? self.managedObjectContext?.save()) as ()??)
		let cache = self.localCache
		
		let graph = RelationshipGraph()
		self.connectCachedRelationships(withGraph: graph)
		graph.prune()

		if graph.count == 0 {
			completion?(nil)
			return
		}
		
		self.willSync(withCache: cache)

		cache.reloadFromServer { error in
			self.managedObjectContext?.perform {
				self.load(into: cache)
                cache.save(reloadingFirst: false) { error in
					self.managedObjectContext?.perform {
						if let err = error {
							print("Error when syncing a record (\(self): \(err)")
						} else {
							for record in graph.consideredObjects {
								record.syncState = .upToDate
							}
							self.syncState = .upToDate
							((try? self.managedObjectContext?.save()) as ()??)
							SyncedContainer.instance.markRecordID(id, inProgress: false)
						}
						completion?(error)
					}
				}
			}
		}
	}
	
	public func deleteSynced(completion: ((Error?) -> Void)? = nil) {
		let db = self.recordID.databaseType ?? SyncedContainer.instance.defaultDatabaseType
		let cache = db.cache.fetch(type: self.cloudKitRecordType, id: self.recordID)

		if let moc = self.managedObjectContext {
			moc.delete(self)
			do {
				try moc.save()
			} catch {
				completion?(error)
			}
		}
		
		cache.delete(completion: completion)
	}
	
	open var syncableFieldNames: [String] {
		return self.entity.attributesByName.values.compactMap { attr in
			if self.isDeviceOnlyAttribute(attr) || attr.name == SyncableManagedObject.cloudKitRecordIDFieldName || attr.name == SyncableManagedObject.syncStateFieldName { return nil }
			return attr.name
		}
	}
	
	open func tempURL(for attribute: NSAttributeDescription) -> URL {
		let filename = attribute.name + "-" + self.uniqueID + ".dat"
		let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
		return baseURL.appendingPathComponent(filename)
	}
	
	@discardableResult open func load(into record: CKLocalCache) -> CKLocalCache {
		let attributes = self.entity.attributesByName
		
		for field in self.syncableFieldNames {
			if let attr = attributes[field], attr.allowsExternalBinaryDataStorage, let data = self.value(forKey: field) as? Data {
				do {
					let url = self.tempURL(for: attr)
					try data.write(to: url)
					record[field] = url
				} catch {
					print("Problem writing a \(field) to a temporary file: \(error)")
				}
			} else {
				record[field] = self.value(forKey: field) as? CKRecordValue
			}
		}
		
		record.syncState = self.syncState
		record.isLoaded = true
        return record
	}
}
