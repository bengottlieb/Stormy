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
	
	open override func awakeFromInsert() {
		super.awakeFromInsert()
		self.setValue(UUID().uuidString, forKey: Self.cloudKitRecordIDFieldName)
		self.setValue(CKLocalCache.SyncState.upToDate.rawValue, forKey: Self.syncStateFieldName)
	}
	
	open func save() {
		if SyncedContainer.mutability.isReadOnlyForCoreData { return }
		if self.hasChanges { self.syncState = .dirty }
	}
	
	open class func predicate(for id: CKRecord.ID) -> NSPredicate {
		return NSPredicate(format: "%K == %@", SyncableManagedObject.cloudKitRecordIDFieldName, id.recordID ?? id.recordName)
	}
	
	open class var parentRelationshipNames: [String] { return [] }
	
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
		
	public var recordID: CKRecord.ID {
		if let name = SyncedContainer.instance.zoneName(for: type(of: self)) {
			let zone = Stormy.instance.zone(named: name)
			return CKRecord.ID(recordName: self.uniqueID, typeName: self.entity.name!, zoneID: zone.zoneID)
		}
		return CKRecord.ID(recordName: self.uniqueID, typeName: self.entity.name!)
	}
	
	func connectCachedRelationships(withGraph graph: SyncableManagedObject.RelationshipGraph) {
		graph.append(self)
		
		for parentName in Self.parentRelationshipNames {
			if let parent = self.value(forKey: parentName) as? SyncableManagedObject {
				self.localCache.setParent(parent.localCache)
				if parent.syncState == .dirty { graph.append(parent) }
				break
			}
		}
		
		for relationship in self.entity.relationshipsByName.values {
			guard let kids = self.value(forKey: relationship.name) as? Set<SyncableManagedObject>, let first = kids.first else { continue }
			
			for parentName in type(of: first).parentRelationshipNames {
				if first.entity.relationshipsByName[parentName]?.destinationEntity?.managedObjectClassName == NSStringFromClass(type(of: self)) {
					kids.forEach { kid in kid.connectCachedRelationships(withGraph: graph) }
				}
			}
		}
	}
	
	public func sync(completion: ((Error?) -> Void)? = nil) {
        DispatchQueue.main.async {
            if SyncedContainer.mutability.isReadOnlyForCoreData { return }

            precondition((self.value(forKey: SyncableManagedObject.cloudKitRecordIDFieldName) as? String)?.isEmpty == false,
                         "Trying to sync a record with no CloudKit recordID: \(self)")
            self.syncState = .dirty
            if !SyncedContainer.mutability.isReadOnlyForCoreData { try? self.managedObjectContext?.save() }
            
            let graph = RelationshipGraph()
            self.connectCachedRelationships(withGraph: graph)
            
            if graph.count == 0 {
                completion?(nil)
                return
            }
            
            graph.queue()
        }
	}
	
    public func deleteSynced(andSave: Bool = true, completion: ((Error?) -> Void)? = nil) {
		if SyncedContainer.mutability.isReadOnlyForCoreData { return }
		let db = self.recordID.databaseType ?? SyncedContainer.instance.defaultDatabaseType
		let cache = db.cache.fetch(type: self.cloudKitRecordType, id: self.recordID)
		
		if let moc = self.managedObjectContext {
			moc.delete(self)
            if andSave {
                do {
                    try moc.save()
                } catch {
                    completion?(error)
                }
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
    
    open var syncableRelationshipNames: [String] {
        return self.entity.relationshipsByName.values.compactMap { rel in
            rel.isToMany ? nil : rel.name
        }
    }
    
	open func tempURL(for attribute: NSAttributeDescription) -> URL {
		let filename = attribute.name + "-" + self.uniqueID + ".dat"
		let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
		return baseURL.appendingPathComponent(filename)
	}
	
	@discardableResult open func load(into cache: CKLocalCache) -> CKLocalCache {
		let attributes = self.entity.attributesByName
		
		for field in self.syncableFieldNames {
			if let attr = attributes[field], attr.allowsExternalBinaryDataStorage, let data = self.value(forKey: field) as? Data {
				do {
					let url = self.tempURL(for: attr)
					try data.write(to: url)
					cache[field] = url
				} catch {
					print("Problem writing a \(field) to a temporary file: \(error)")
				}
			} else {
				cache[field] = self.value(forKey: field) as? CKRecordValue
			}
		}
        
        for relationshipName in syncableRelationshipNames {
            let myValue = self.value(forKey: relationshipName) as? SyncableManagedObject
            let cacheValue = cache[relationshipName] as? CKRecord.Reference
            
            if myValue == nil, cacheValue != nil {
                cache.changedKeys.insert(relationshipName)
            } else if myValue != nil, cacheValue != nil {
                cache.changedKeys.insert(relationshipName)
            } else if myValue?.isSame(as: cacheValue) == false {
                cache.changedKeys.insert(relationshipName)
            }
        }
		
		cache.syncState = self.syncState
		cache.isLoaded = true
		return cache
	}
    
    func isSame(as relationship: CKRecord.Reference?) -> Bool {
        recordID == relationship?.recordID
    }
}
