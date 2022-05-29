//
//  CKLocalCache.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/19/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit


extension CKDatabase.Scope {
	static var caches: [CKDatabase.Scope: Cache] = [:]
	
	public var cache: Cache {
		if let cache = CKDatabase.Scope.caches[self] { return cache }
		
		let cache = Cache(type: self)
		CKDatabase.Scope.caches[self] = cache
		return cache
	}
}

extension CKDatabase.Scope {
	public class Cache {
        let queue = DispatchQueue(label: "CKDatabase-Cache-Queue")
		var type: CKDatabase.Scope
		init(type: CKDatabase.Scope) {
			self.type = type
		}

        public func fetch(type: String, id: CKRecord.ID) -> CKLocalCache {
            queue.sync {
                if let cached = self.cache[id], let existing = cached.cache { return existing }
                
                let recordCache = CKLocalCache(type: type, id: id, in: self.type)
                self.cache[id] = Shared(cache: recordCache)
                return recordCache
            }
		}
		
        public func fetch(record: CKRecord?, sync: Bool = true) -> CKLocalCache? {
            if sync {
                return queue.sync { syncFetch(record: record) }
            } else {
                return syncFetch(record: record)
            }
		}
        
        private func syncFetch(record: CKRecord?) -> CKLocalCache? {
            guard let record = record else { return nil }
            if let existing = self.cache[record.recordID]?.cache {
                existing.originalRecord = record
                existing.updateFromOriginal()
                return existing
            }
            
            let recordCache = CKLocalCache(record: record, in: self.type)
            self.cache[record.recordID] = Shared(cache: recordCache)
            return recordCache
        }
		
        public func fetch(reference: CKRecord.Reference, sync: Bool = true) -> CKLocalCache {
            if sync {
                return queue.sync { syncFetch(reference: reference) }
            } else {
                return syncFetch(reference: reference)
            }
        }
        
        private func syncFetch(reference: CKRecord.Reference) -> CKLocalCache {
            if let existing = self.cache[reference.recordID]?.cache { return existing }
            
            let recordCache = CKLocalCache(reference: reference, in: self.type)
            self.cache[reference.recordID] = Shared(cache: recordCache)
            return recordCache
		}
		
		private var cache: [CKRecord.ID: Shared] = [:]
		
		struct Shared {
			weak var cache: CKLocalCache?
		}
	}
}



open class CKLocalCache: CustomStringConvertible, Equatable {
	open var typeName: CKRecord.RecordType!
	open var recordID: CKRecord.ID
	open var database: CKDatabase.Scope
	open var changedKeys: Set<String> = []
	open var changedValues: [String: CKRecordValue] = [:]
	open var originalRecord: CKRecord? { didSet { if let type = self.originalRecord?.recordType { self.typeName = type }}}
	open var recordZone: CKRecordZone? { return Stormy.instance.zone(withID: self.recordID.zoneID) }
	open var hasChanges: Bool { return self.changedKeys.count > 0 || childrenChanged }
	open var existsOnServer: Bool { return self.originalRecord != nil }
	public var isLoaded = false
	public var syncState = CKLocalCache.SyncState.upToDate
	
	private var childrenChanged = false
	public private(set) var parent: CKLocalCache?
	private var children: [CKLocalCache] = []
    private func reference(action: CKRecord.ReferenceAction = .none) -> CKRecord.Reference {
		return CKRecord.Reference(recordID: self.recordID, action: action)
	}
	
	fileprivate init(reference: CKRecord.Reference, in database: CKDatabase.Scope) {
		self.recordID = reference.recordID
		self.database = database
		self.typeName = reference.recordID.typeName
	}
	
	fileprivate init(type: String, id: CKRecord.ID, in database: CKDatabase.Scope = .private) {
		self.originalRecord = nil
		self.typeName = type
		self.recordID = id
		self.database = database
	}
	
	fileprivate init(record: CKRecord, in database: CKDatabase.Scope) {
		self.originalRecord = record
		self.database = database
		self.typeName = record.recordType
		self.recordID = record.recordID
		self.updateFromOriginal()
	}
	
	func updateFromOriginal(overrwritingChanges: Bool = true) {
		guard let original = self.originalRecord else { return }
		
		if overrwritingChanges {
			self.changedValues = [:]
			self.changedKeys = []
		}
		if #available(OSX 10.12, iOS 10.0, *), let ref = original.parent {
            self.parent = database.cache.fetch(reference: ref, sync: false)
        }
        
		if !self.childrenChanged, let kids = original[Stormy.childReferencesFieldName] as? [CKRecord.Reference] {
			self.children = kids.map { self.database.cache.fetch(reference: $0, sync: false) }
		}
	}
	
	open func didSave(to record: CKRecord? = nil) {
		if let rec = record { self.originalRecord = rec }
		self.clearChanges()
	}
	
	open func clearChanges() {
		self.changedValues = [:]
		self.changedKeys = []
		self.childrenChanged = false
	}
	
	open var allKeys: [String] {
		var base = Set(self.originalRecord?.allKeys() ?? [])
		base.formUnion(self.changedKeys)
		return Array(base).sorted()
	}
	
	var decendents: [CKLocalCache] {
		var decendents = self.children
		for child in self.children {
			decendents += child.decendents
		}
		return decendents
	}
	
	open func save(reloadingFirst: Bool = true, evenIfNotDirty: Bool = false, completion: ((Error?) -> Void)? = nil) {
		if SyncedContainer.mutability.isReadOnlyForCloudOps {
			completion?(nil)
			return
		}
		if reloadingFirst, self.existsOnServer {
			self.reloadFromServer(andThenSave: true, completion: completion)
			return
		}
		
		if !self.hasChanges, !evenIfNotDirty { completion?(nil); return }
		
		let allCaches = [self] + self.decendents.filter { $0.syncState != .upToDate }
		let caches = allCaches.byRemovingDuplicates()
		
		let op = CKModifyRecordsOperation(recordsToSave: caches.compactMap { ($0.hasChanges || evenIfNotDirty) ? $0.updatedRecord() : nil }, recordIDsToDelete: nil)
		Stormy.instance.startLongRunningTask()
		op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
			if Stormy.shouldReturn(after: error, operation: op, in: self.database, completion: completion) {
				Stormy.instance.completeLongRunningTask()
				return
			}
			if let err = error?.rootCKError(for: self.recordID), err.code == .serverRecordChanged {
				self.reloadFromServer(andThenSave: true, completion: completion)
			} else {
				for record in caches {
					let remote = saved?.first(where: { $0.recordID == record.recordID })
					record.didSave(to: remote)
				}
				completion?(error?.rootCKError(for: self.recordID) ?? error)
				Stormy.instance.completeLongRunningTask()
			}
		}
		Stormy.instance.queue(operation: op, in: self.database)
	}
	
    open func setParent(_ parent: CKLocalCache?, for key: String) {
		if let record = parent {
			//self.parentReference = CKRecord.Reference(recordID: record.recordID, action: .none)
			self.parent = parent
			if !record.children.contains(self) {
				record.children.append(self)
				record.childrenChanged = true
			}
		} else {
			if let index = self.parent?.children.firstIndex(of: self) {
				self.parent?.children.remove(at: index)
			}
			self.parent = nil
		}
	}
	
	open func reloadFromServer(andThenSave: Bool = false, completion: ((Error?) -> Void)?) {
		Stormy.instance.fetch(self.recordID, in: self.database) { records, error in
			if let found = records.first?.originalRecord {
				self.originalRecord = found
				
				self.changedKeys = self.changedKeys.filter { key in return !self.areEqual(self.changedValues[key], found[key]) }
			}
			
			let isUnknownItem = error?.rootCKError(for: self.recordID)?.code == .unknownItem
			if andThenSave, (error == nil || isUnknownItem) {
				self.save(reloadingFirst: false, completion: completion)
			} else {
				completion?(isUnknownItem ? nil : error)
			}
		}
	}
	
	var childReferences: [CKRecord.Reference]? {
		let refs = self.children.map { $0.reference() }
		return refs.isEmpty ? nil : refs
	}
	
	open var description: String {
		var result = ""
		for key in self.allKeys {
			result += "\t\(key): \t"
			if let value = self[key] {
				if let data = value as? Data {
					result += "<\(data.count) bytes>"
				} else {
					result += "\(value)"
				}
			} else {
				result += "nil"
			}
			result += "\n"
		}
		return result
	}
	
	var descendentIDs: [CKRecord.ID] {
		self.children.flatMap { $0.descendentIDs } + [self.recordID]
	}
	
	public func delete(ignoreOnServerState: Bool = true, completion: ((Error?) -> Void)? = nil) {
		if (!self.existsOnServer && !ignoreOnServerState) || SyncedContainer.mutability.isReadOnlyForCloudOps {
			completion?(nil)
			return
		}
		
		let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: self.descendentIDs )
        print("Deleting \(self.descendentIDs.count) records")
		Stormy.instance.startLongRunningTask()
		op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
			if !Stormy.shouldReturn(after: error, operation: op, in: self.database, completion: completion) { completion?(error) }
			Stormy.instance.completeLongRunningTask()
		}
		Stormy.instance.queue(operation: op, in: self.database)
	}
	
	
    open func updatedRecord(using managed: SyncableManagedObject? = nil) -> CKRecord? {
		if self.typeName == nil { return nil }
//        var pertinentFields: [String]!
//        
//        if let mgd = managed { pertinentFields = type(of: mgd).pertinentRelationshipNames }
//        if pertinentFields == nil { pertinentFields = SyncableManagedObject.pertinentNames(for: self.typeName, in: managed?.moc ?? SyncedContainer.instance.viewContext) }
//        if pertinentFields == nil { return nil }
//        
		let newRecord = self.originalRecord ?? CKRecord(recordType: self.typeName, recordID: self.recordID)
		
		for key in self.changedKeys {
			if let current = newRecord[key], let new = self.changedValues[key] {
				if !areEqual(current, new) {
					newRecord[key] = self.changedValues[key]
				}
			} else if newRecord[key] == nil, self.changedValues[key] == nil {
				//both nil, don't do anything
            } else if let value = self.changedValues[key] as? CKRecord.Reference {
                newRecord[key] = value
            } else {
				newRecord[key] = self.changedValues[key]
			}
		}
		
		if #available(OSX 10.12, iOS 10.0, *) {
			let parent = self.parent?.reference(action: .none)
			if parent != newRecord.parent { newRecord.parent = parent }
			if newRecord[Stormy.childReferencesFieldName] != self.childReferences { newRecord[Stormy.childReferencesFieldName] = self.childReferences }
		}
		
		return newRecord
	}
	
	open subscript(_ key: String) -> Any? {
		get {
			let value = self.changedKeys.contains(key) ? self.changedValues[key] : self.originalRecord?[key]
			if let asset = value as? CKAsset { return asset.fileURL! }
			return value
		}
		set {
			var savedValue = newValue
			if let url = newValue as? URL, url.isFileURL { savedValue = CKAsset(fileURL: url) }
			
			if self.areEqual(self.originalRecord?[key], savedValue) {		// back to the old value
				self.changedKeys.remove(key)
				self.changedValues.removeValue(forKey: key)
				return
			}
			
			if self.areEqual(self.originalRecord?[key], savedValue) { return } 			// no changes
			
			if let value = savedValue as? CKRecordValue {
				self.changedValues[key] = value
				self.changedKeys.insert(key)
			} else if savedValue == nil {
				self.changedKeys.insert(key)
				self.changedValues.removeValue(forKey: key)
			}
		}
	}
	
	/* String, Date, Data, Bool, Int, UInt, Float, Double, [U]Int8 et al, CKReference / Record.Reference, CKAsset, CLLocation, Array */
	open func areEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
		if let left = lhs as? String, let right = rhs as? String { return left == right }
		if let left = lhs as? Date, let right = rhs as? Date { return left == right }
		if let left = lhs as? Data, let right = rhs as? Data { return left == right }
		if let left = lhs as? Bool, let right = rhs as? Bool { return left == right }
		if let left = lhs as? Int, let right = rhs as? Int { return left == right }
		if let left = lhs as? Double, let right = rhs as? Double { return left == right }
		if let left = lhs as? CKRecord.Reference, let right = rhs as? CKRecord.Reference { return left == right }
		if let left = (lhs as? CKAsset)?.fileURL!, let right = (rhs as? CKAsset)?.fileURL! { return left.isSameFile(as: right) }
		if let left = lhs as? CLLocation, let right = rhs as? CLLocation { return left == right }
		if let left = lhs as? [CKRecordValue], let right = rhs as? [CKRecordValue] {
			if left.count != right.count { return false }
			for (leftItem, rightItem) in zip(left, right) { if !self.areEqual(leftItem, rightItem) { return false }}
			return true
		}
		return false
	}
	
	public static func ==(lhs: CKLocalCache, rhs: CKLocalCache) -> Bool {
		return lhs.recordID == rhs.recordID
	}
}

extension CKLocalCache {
	public enum SyncState: Int { case upToDate, dirty, syncing }
}

extension Array where Element: Equatable {
	func byRemovingDuplicates() -> [Element] {
		var results: [Element] = []
		
		for item in self {
			if !results.contains(item) { results.append(item) }
		}
		
		return results
	}
}
