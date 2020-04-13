//
//  SyncedPersistentContainer.swift
//  ContextSync
//
//  Created by Ben Gottlieb on 11/2/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CoreData
import CloudKit

@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
open class AppGroupPersistentContainer: NSPersistentContainer {
	static var applicationGroupIdentifier: String?
	
	override open class func defaultDirectoryURL() -> URL {
		if let identifier = AppGroupPersistentContainer.applicationGroupIdentifier, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
			return url
		}
		
		return super.defaultDirectoryURL()
	}
}

@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
open class SyncedContainer {
	public enum State: Int { case offline, ready, synchronizing }
	
	public static var instance: SyncedContainer!
	
	public var state = State.offline { didSet { if state != oldValue { self.notifyAboutStateChange() }}}
	public let container: NSPersistentContainer
	public var viewContext: NSManagedObjectContext { return self.container.viewContext }
	public var zoneNames: [String] = []
	public var syncedObjects: [String: EntityInfo] = [:]
	public var defaultDatabaseType = CKDatabase.Scope.private
	
	public var isInExtension: Bool {
		let extensionDictionary = Bundle.main.infoDictionary?["NSExtension"]
		return extensionDictionary is NSDictionary
	}
	
	public struct EntityInfo {
		let type: SyncableManagedObject.Type
		var zoneName: String?
		var zoneID: CKRecordZone.ID?
		var database: CKDatabase.Scope
		
		init(entity: SyncableManagedObject.Type, zoneName: String? = nil, database: CKDatabase.Scope = .private) {
			self.type = entity
			self.zoneName = zoneName
			self.database = database
		}
	}
	
	public struct Notifications {
		public static let containerStateChanged = Notification.Name("containerStateChanged")
		public static let containerInitialSetupComplete = Notification.Name("initialSetupComplete")
		public static let containerInitialSyncComplete = Notification.Name("initialSyncComplete")
	}
	
	var queue = DispatchQueue(label: "SyncedContainerQueue")
	
	public static func setup(name: String, managedObjectModel model: NSManagedObjectModel? = nil, bundle: Bundle = .main, appGroupIdentifier: String? = nil) {
		self.instance = SyncedContainer(name: name, managedObjectModel: model, bundle: bundle, appGroupIdentifier: appGroupIdentifier)
	}
	
	public init(name: String, managedObjectModel model: NSManagedObjectModel? = nil, bundle: Bundle = .main, appGroupIdentifier: String? = nil) {
		AppGroupPersistentContainer.applicationGroupIdentifier = appGroupIdentifier
		self.container = AppGroupPersistentContainer(name: name, managedObjectModel: model ?? NSManagedObjectModel(contentsOf: bundle.url(forResource: name, withExtension: "momd")!)!)
		Stormy.instance.recordIDTypeSeparator = "/"
		self.queue.suspend()
		self.container.loadPersistentStores { desc, error in
			self.viewContext.automaticallyMergesChangesFromParent = true
			self.queue.resume()
		}
	}
	
	public func register(entity: SyncableManagedObject.Type, zoneName: String? = nil, database: CKDatabase.Scope = .private) {
		guard let entityName = entity.entity().name else {
			assert(false, "Entity name required for \(entity)")
			return
		}
		
		assert(entity.entity().attributesByName[SyncableManagedObject.cloudKitRecordIDFieldName]?.attributeType == .stringAttributeType, "Trying to register \(entity), but its \(SyncableManagedObject.cloudKitRecordIDFieldName) ID field is not a string")
		let syncStatusType = entity.entity().attributesByName[SyncableManagedObject.syncStateFieldName]?.attributeType
		assert(syncStatusType == .integer16AttributeType || syncStatusType == .integer32AttributeType || syncStatusType == .integer64AttributeType, "Trying to register \(entity), but its \(SyncableManagedObject.syncStateFieldName) field is not an integer")

		if entity.parentRelationshipName == nil {
			for relationship in entity.entity().relationshipsByName.values {
				if !relationship.isToMany, let inverse = relationship.inverseRelationship, inverse.isToMany {
					print("****** WARNING ********\nAdding an entity (\(entityName)) with no parentRelationshipName that appears to have a parent relationship to \(inverse.entity.name ?? "--")")
				}
			}
		}
		
		self.syncedObjects[entityName] = EntityInfo(entity: entity, zoneName: zoneName, database: database)
	}
	
	public func setupCloud(identifier: String, includingSubscriptions: Bool = true, andConnect: Bool = true, completion: (() -> Void)? = nil) {
		assert(self.syncedObjects.count > 0, "Please register entities before setting up the cloud identifier.")
		
		let syncCompletion = {
			self.state = .ready
			DispatchQueue.main.async { NotificationCenter.default.post(name: Notifications.containerInitialSetupComplete, object: self) }
			if !self.isInExtension {
				self.pullChanges() {
					DispatchQueue.main.async { NotificationCenter.default.post(name: Notifications.containerInitialSyncComplete, object: self) }
					self.checkForUnsyncedObjects()
					completion?()
				}
			}
		}
		
		
		self.queue.async {
			self.zoneNames = Array(Set(self.syncedObjects.values.compactMap({ $0.zoneName })))
			
			Stormy.instance.setup(identifier: identifier, zones: self.zoneNames, andConnect: andConnect) 
			Stormy.instance.queue {
				if includingSubscriptions {
					#if os(iOS)
					var dbs: Set<CKDatabase.Scope> = []
					for obj in self.syncedObjects.values { dbs.insert(obj.database) }
					self.setupSubscriptions(on: Array(dbs)) { error in
						syncCompletion()
					}
					#endif
				} else {
					syncCompletion()
				}
			}
		}
	}
	
	func notifyAboutStateChange() {
		DispatchQueue.main.async { NotificationCenter.default.post(name: Notifications.containerStateChanged, object: self) }
	}
	
	public func pullChanges(completion: (() -> Void)? = nil) {
		DispatchQueue.global(qos: .userInitiated).async {
			self.state = .synchronizing
			
			for zoneName in self.zoneNames {
				let zone = Stormy.instance.zone(named: zoneName)
				let token = Stormy.instance.serverFetchTokens[zone.zoneID]
				self.queue.suspend()
				
				Stormy.instance.fetchChanges(in: zone, database: .private, since: token, fetching: nil) { result in
					switch result {
					case .failure(let err):
						print("Error while pulling changes: \(err)")
						
					case .success(let changes):
						var changedObjects: [SyncableManagedObject] = []
						
						self.container.performBackgroundTask { moc in
							for record in changes.records {
								let object = moc.object(ofType: record.typeName, withID: record.recordID)
								object.read(from: record)
								changedObjects.append(object)
							}
							
							for object in changedObjects {
								guard let parentName = type(of: object).parentRelationshipName else { continue }
								let record = object.localCache
								if let parent = record.parent?.lookupObject(in: moc) {
									object.setValue(parent, forKey: parentName)
								}
							}
							
							for recordID in changes.deletedIDs {
								for (entityName, _) in self.syncedObjects {
									if let object = moc.lookupObject(ofType: entityName, withID: recordID) {
										moc.delete(object)
									}
								}
							}
							
							Stormy.instance.serverFetchTokens[zone.zoneID] = changes.tokenData
							try! moc.save()
							self.queue.resume()
						}
					}
				}
			}
			
			self.queue.async {
				self.state = .ready
				completion?()
			}
		}
	}
	
	func zoneName(for entity: SyncableManagedObject.Type) -> String? {
		return self.syncedObjects[entity.entity().name!]?.zoneName
	}
}

@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
extension CKLocalCache {
	public func object(in moc: NSManagedObjectContext) -> SyncableManagedObject? {
		if let type = self.typeName { return moc.object(ofType: type, withID: self.recordID) }
		return nil
	}
	
	public func lookupObject(in moc: NSManagedObjectContext) -> SyncableManagedObject? {
		if let type = self.typeName { return moc.lookupObject(ofType: type, withID: self.recordID) }
		return nil
	}
}

@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
extension NSManagedObjectContext {
	public func lookupObject(ofType entityName: String, withID id: CKRecord.ID) -> SyncableManagedObject? {
		let entity = SyncedContainer.instance.syncedObjects[entityName]?.type
		let request = NSFetchRequest<SyncableManagedObject>(entityName: entityName)
		request.fetchLimit = 1
		request.predicate = entity?.predicate(for: id)
		
		do {
			let result = try self.fetch(request)
			return result.first
		} catch {
			print("Error when fetching: \(error)")
			return nil
		}
	}
	
	public func object(ofType entityName: String, withID id: CKRecord.ID) -> SyncableManagedObject {
		if let object = self.lookupObject(ofType: entityName, withID: id) { return object }
		
		let new = NSEntityDescription.insertNewObject(forEntityName: entityName, into: self) as! SyncableManagedObject
		
		if let uniqueID = id.recordID { new.uniqueID = uniqueID }
		return new
	}
}
