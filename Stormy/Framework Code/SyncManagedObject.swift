//
//  SyncManagedObject.swift
//  Stormy
//
//  Created by Ben Gottlieb on 10/6/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreData
import CloudKit

public protocol SyncManagedObject: CloudLoadableManagedObject {
	static var changeTokenSettingsKey: String { get }				// we'll store our server change token here
	static var zone: CKRecordZone? { get }
}

public protocol CloudLoadableManagedObject: class {
	static var recordIDField: String { get }						// we'll use this value to echo a record's recordID
}

@available(iOSApplicationExtension 10.0, *)
@available(OSXApplicationExtension 10.12, *)
extension SyncManagedObject where Self: NSManagedObject {
	static public func syncChanges(zone: CKRecordZone?, database: DatabaseType, in container: NSPersistentContainer, completion: ((Error?) -> Void)? = nil) {
		if !Stormy.instance.available { completion?(Stormy.StormyError.notSignedIn); return }
		let tokenData = UserDefaults.standard.data(forKey: self.changeTokenSettingsKey)
		Stormy.instance.fetchChanges(in: zone, database: database, since: tokenData, fetching: nil) { changes, error in
			UserDefaults.standard.set(changes?.tokenData, forKey: self.changeTokenSettingsKey)
			
			container.performBackgroundTask { moc in
				for id in changes?.deletedIDs ?? [] {
					if let object = self.fetchObject(withID: id, in: moc) { moc.delete(object) }
				}
				
				for change in changes?.records ?? [] {
					if let object = self.fetchObject(withID: change.recordID, in: moc) {
						object.load(from: change)
					} else if let object = self.insert(into: moc) {
						object.setValue(change.recordID.recordName, forKey: self.recordIDField)
						object.load(from: change)
					} else {
						print("Failed to create a record of type \(self.entity().name!) for \(change)")
					}
				}
				
				do {
					try moc.save()
					completion?(error)
				} catch {
					print("Error while saving context: \(error)")
					completion?(error)
				}
			}
		}
	}
	
	public static func fetchObject(withID id: CKRecord.ID, in moc: NSManagedObjectContext) -> Self? {
		let entityName = self.entity().name!
		let request = NSFetchRequest<Self>(entityName: entityName)
		request.predicate = NSPredicate(format: "%K == %@", argumentArray: [self.recordIDField, id.recordName])
		
		do {
			return try request.execute().first
		} catch {
			print("Error while fetching a \(entityName): \(error)")
			return nil
		}
	}
	
	public var recordID: CKRecord.ID {
		if let zone = type(of: self).zone {
			return CKRecord.ID(recordName: self.value(forKey: type(of: self).recordIDField) as! String, zoneID: zone.zoneID)
		}
		return CKRecord.ID(recordName: self.value(forKey: type(of: self).recordIDField) as! String)
	}
	
	public func generateCacheRecord() -> CKLocalCache {
		let cache = DatabaseType.private.cache.fetch(type: self.entity.name!, id: self.recordID)
		self.populate(cacheRecord: cache)
		return cache
	}
	
	public func saveToCloud(completion: ((Error?) -> Void)?) {
		if !Stormy.instance.available { completion?(Stormy.StormyError.notSignedIn); return }
		let cache = DatabaseType.private.cache.fetch(type: self.entity.name!, id: self.recordID)
		self.populate(cacheRecord: cache)
		cache.reloadFromServer(andThenSave: true, completion: completion)
	}
}

@available(iOSApplicationExtension 10.0, *)
@available(OSXApplicationExtension 10.12, *)
extension CloudLoadableManagedObject where Self: NSManagedObject {
	public static func insert(into moc: NSManagedObjectContext) -> Self? {
		let entityName = self.entity().name!
		return NSEntityDescription.insertNewObject(forEntityName: entityName, into: moc) as? Self
	}
	
	public func load(from cachedRecord: CKLocalCache) {
		for (name, attribute) in self.entity.attributesByName {
			if let value = cachedRecord[name] {
				self.setCloudValue(value, forAttribute: attribute)
			}
		}
	}
	
	public func populate(cacheRecord: CKLocalCache) {
		let idField = type(of: self).recordIDField
		for (name, _) in self.entity.attributesByName {
			if name != idField, let value = self.value(forKey: name) {
				cacheRecord[name] = value
			}
		}
	}
	
	func setCloudValue(_ value: Any, forAttribute attr: NSAttributeDescription) {
		switch attr.attributeType {
		case .undefinedAttributeType: break
		case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
			if let val = value as? Int { self.setValue(val, forKey: attr.name) }
		case .decimalAttributeType, .doubleAttributeType, .floatAttributeType:
			if let val = value as? Double { self.setValue(val, forKey: attr.name) }
			
		case .stringAttributeType: if let val = value as? String { self.setValue(val, forKey: attr.name) }
		case .booleanAttributeType: if let val = value as? Bool { self.setValue(val, forKey: attr.name) }
		case .dateAttributeType: if let val = value as? Date { self.setValue(val, forKey: attr.name) }
		case .binaryDataAttributeType: if let val = value as? Data { self.setValue(val, forKey: attr.name) }
		case .UUIDAttributeType: if let val = value as? UUID { self.setValue(val, forKey: attr.name) }
		case .URIAttributeType: if let val = value as? URL { self.setValue(val, forKey: attr.name) }
		case .transformableAttributeType: self.setValue(value, forKey: attr.name)
		case .objectIDAttributeType: break
		}
	}
}
