//
//  CKRecord.Cache.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/19/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

extension DatabaseType {
	public class Cache {
		var type: DatabaseType
		init(type: DatabaseType) {
			self.type = type
		}
		
		public func fetch(type: String, id: CKRecord.ID) -> CKRecord.Cache {
			if let existing = self.cache[id]?.cache { return existing }
			
			let recordCache = CKRecord.Cache(type: type, id: id, in: self.type)
			self.cache[id] = Shared(cache: recordCache)
			return recordCache
		}
		
		public func fetch(record: CKRecord?) -> CKRecord.Cache? {
			guard let record = record else { return nil }
			if let existing = self.cache[record.recordID]?.cache {
				existing.originalRecord = record
				existing.updateFromOriginal()
				return existing
			}
			
			let recordCache = CKRecord.Cache(record: record, in: self.type)
			self.cache[record.recordID] = Shared(cache: recordCache)
			return recordCache
		}
		
		public func fetch(reference: CKRecord.Reference) -> CKRecord.Cache {
			if let existing = self.cache[reference.recordID]?.cache { return existing }
			
			let recordCache = CKRecord.Cache(reference: reference, in: self.type)
			self.cache[reference.recordID] = Shared(cache: recordCache)
			return recordCache
		}
		
		var cache: [CKRecord.ID: Shared] = [:]
		
		struct Shared {
			weak var cache: CKRecord.Cache?
		}
	}
}


extension CKRecord {
	
	open class Cache: CustomStringConvertible, Equatable {
		open var typeName: CKRecord.RecordType!
		open var recordID: CKRecord.ID
		open var database: DatabaseType
		open var changedKeys: Set<String> = []
		open var changedValues: [String: CKRecordValue] = [:]
		open var originalRecord: CKRecord?
		open var recordZone: CKRecordZone? { return Stormy.instance.zone(withID: self.recordID.zoneID) }
		open var isDirty: Bool { return self.changedKeys.count > 0 || childrenChanged }
		open var existsOnServer: Bool { return self.originalRecord != nil }
		
		
		private var childrenChanged = false
		private var parent: CKRecord.Cache?
		private var children: [CKRecord.Cache] = []
		private func reference(action: CKRecord_Reference_Action = .none) -> CKRecord.Reference { return CKRecord.Reference(recordID: self.recordID, action: action) }
		
		fileprivate init(reference: CKRecord.Reference, in database: DatabaseType) {
			self.recordID = reference.recordID
			self.database = database
		}
		
		fileprivate init(type: String, id: CKRecord.ID, in database: DatabaseType = .private) {
			self.originalRecord = nil
			self.typeName = type
			self.recordID = id
			self.database = database
		}
		
		fileprivate init(record: CKRecord, in database: DatabaseType) {
			self.originalRecord = record
			self.database = database
			self.typeName = record.recordType
			self.recordID = record.recordID
			self.updateFromOriginal()
		}
		
		func updateFromOriginal() {
			guard let original = self.originalRecord else { return }
			if #available(OSXApplicationExtension 10.12, iOS 10.0, *), let ref = original.parent { self.parent = database.cache.fetch(reference: ref) }
			if let kids = original[Stormy.childReferencesFieldName] as? [CKRecord.Reference] {
				self.children = kids.map { self.database.cache.fetch(reference: $0) }
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
		
		var decendents: [CKRecord.Cache] {
			var decendents = self.children
			for child in self.children {
				decendents += child.decendents
			}
			return decendents
		}
		
		open func save(reloadingFirst: Bool = true, completion: ((Error?) -> Void)? = nil) {
			if reloadingFirst, self.existsOnServer {
				self.reloadFromServer(andThenSave: true, completion: completion)
				return
			}
			
			if !self.isDirty { completion?(nil); return }
			
			let caches = [self] + self.decendents
			let op = CKModifyRecordsOperation(recordsToSave: caches.compactMap { $0.isDirty ? $0.updatedRecord() : nil }, recordIDsToDelete: nil)
			op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
				if Stormy.shouldReturn(after: error, operation: op, in: self.database, completion: completion) { return }
				if let err = error?.rootCKError(for: self.recordID), err.code == .serverRecordChanged {
					self.reloadFromServer(andThenSave: true, completion: completion)
				} else {
					for record in caches {
						record.didSave()
					}
					completion?(error?.rootCKError(for: self.recordID) ?? error)
				}
			}
			Stormy.instance.queue(operation: op, in: self.database)
		}
		
		open func setParent(_ parent: CKRecord.Cache?) {
			if let record = parent {
				//self.parentReference = CKRecord.Reference(recordID: record.recordID, action: .none)
				self.parent = parent
				record.children.append(self)
				record.childrenChanged = true
			} else {
				if let index = self.parent?.children.index(of: self) {
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
					result += "\(value)"
				} else {
					result += "nil"
				}
				result += "\n"
			}
			return result
		}
		
		public func delete(completion: ((Error?) -> Void)? = nil) {
			if !self.existsOnServer {
				completion?(nil)
				return
			}
			
			let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [self.recordID])
			op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
				if Stormy.shouldReturn(after: error, operation: op, in: self.database, completion: completion) { return }
				completion?(error)
			}
			Stormy.instance.queue(operation: op, in: self.database)
		}
		
		
		open func updatedRecord() -> CKRecord? {
			if self.typeName == nil { return nil }
			let newRecord = self.originalRecord ?? CKRecord(recordType: self.typeName, recordID: self.recordID)
			
			for key in self.changedKeys {
				newRecord[key] = self.changedValues[key]
			}
			
			if #available(OSXApplicationExtension 10.12, iOS 10.0, *) {
				newRecord.parent = self.parent?.reference(action: .none)
				newRecord[Stormy.childReferencesFieldName] = self.childReferences
			}

			return newRecord
		}
		
		open subscript(_ key: String) -> Any? {
			get {
				let value = self.changedKeys.contains(key) ? self.changedValues[key] : self.originalRecord?[key]
				if let asset = value as? CKAsset { return asset.fileURL }
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
			if let left = lhs as? CKAsset, let right = rhs as? CKAsset { return left.fileURL.isSameFile(as: right.fileURL) }
			if let left = lhs as? CLLocation, let right = rhs as? CLLocation { return left == right }
			if let left = lhs as? [CKRecordValue], let right = rhs as? [CKRecordValue] {
				if left.count != right.count { return false }
				for (leftItem, rightItem) in zip(left, right) { if !self.areEqual(leftItem, rightItem) { return false }}
				return true
			}
			return false
		}
		
		public static func ==(lhs: Cache, rhs: Cache) -> Bool {
			return lhs.recordID == rhs.recordID
		}
	}
}

