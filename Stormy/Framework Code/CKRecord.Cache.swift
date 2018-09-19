//
//  CKRecord.Cache.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/19/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

extension CKRecord {
	open class Cache: CustomStringConvertible {
		open var typeName: CKRecord.RecordType
		open var recordID: CKRecord.ID
		open var database: Stormy.DatabaseType
		open var changedKeys: Set<String> = []
		open var changedValues: [String: CKRecordValue] = [:]
		open var originalRecord: CKRecord?
		open var recordZone: CKRecordZone? { return Stormy.instance.zone(withID: self.recordID.zoneID) }
		open var isDirty: Bool { return self.changedKeys.count > 0 }
		open var existsOnServer: Bool { return self.originalRecord != nil }
		
		public private(set) var parentReference: CKRecord.Reference?
		
		public init(type: String, id: CKRecord.ID, in database: Stormy.DatabaseType = .private) {
			self.originalRecord = nil
			self.typeName = type
			self.recordID = id
			self.database = database
		}
		
		public init?(record: CKRecord?, in database: Stormy.DatabaseType) {
			self.originalRecord = record
			self.database = database
			guard let record = record else {
				self.typeName = ""
				self.recordID = CKRecord.ID(recordName: "-")
				return nil
			}
			self.typeName = record.recordType
			self.recordID = record.recordID
			if #available(OSXApplicationExtension 10.12, iOS 10.0, *) { self.parentReference = record.parent }
		}
		
		open func didSave(to record: CKRecord? = nil) {
			if let rec = record { self.originalRecord = rec }
			self.clearChanges()
		}
		
		open func clearChanges() {
			self.changedValues = [:]
			self.changedKeys = []
		}
		
		open var allKeys: [String] {
			var base = Set(self.originalRecord?.allKeys() ?? [])
			base.formUnion(self.changedKeys)
			return Array(base).sorted()
		}
		
		open func save(reloadingFirst: Bool = true, completion: ((Error?) -> Void)? = nil) {
			if reloadingFirst, self.existsOnServer {
				self.reloadFromServer(andThenSave: true, completion: completion)
				return
			}
			
			if !self.isDirty { completion?(nil); return }
			let op = CKModifyRecordsOperation(recordsToSave: [self.updatedRecord()], recordIDsToDelete: nil)
			op.modifyRecordsCompletionBlock = { saved, recordIDs, error in
				if Stormy.shouldReturn(after: error, operation: op, in: self.database, completion: completion) { return }
				if let err = error as NSError?, err.code == 2, err.domain == CKErrorDomain {
					self.reloadFromServer(andThenSave: true, completion: completion)
				} else {
					self.didSave()
					completion?(error)
				}
			}
			Stormy.instance.queue(operation: op, in: self.database)
		}
		
		open func setParent(_ parent: CKRecord.Cache?) {
			if let record = parent {
				self.parentReference = CKRecord.Reference(recordID: record.recordID, action: .none)
			} else {
				self.parentReference = nil
			}
		}
		
		open func reloadFromServer(andThenSave: Bool = false, completion: ((Error?) -> Void)?) {
			Stormy.instance.fetch(self.recordID, in: self.database) { records, error in
				if let found = records.first?.originalRecord {
					self.originalRecord = found
					
					self.changedKeys = self.changedKeys.filter { key in return !self.areEqual(self.changedValues[key], found[key]) }
				}
				
				if andThenSave, (error == nil || error?.rootCKError?.code == .unknownItem) {
					self.save(reloadingFirst: false, completion: completion)
				} else {
					completion?(error)
				}
			}
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
		
		
		open func updatedRecord() -> CKRecord {
			let newRecord = self.originalRecord ?? CKRecord(recordType: self.typeName, recordID: self.recordID)
			
			for key in self.changedKeys {
				newRecord[key] = self.changedValues[key]
			}
			
			if #available(OSXApplicationExtension 10.12, iOS 10.0, *) { newRecord.parent = self.parentReference }

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
			if let left = lhs as? CKAsset, let right = rhs as? CKAsset { return left == right }
			if let left = lhs as? CLLocation, let right = rhs as? CLLocation { return left == right }
			if let left = lhs as? [CKRecordValue], let right = rhs as? [CKRecordValue] {
				if left.count != right.count { return false }
				for (leftItem, rightItem) in zip(left, right) { if !self.areEqual(leftItem, rightItem) { return false }}
				return true
			}
			return false
		}
	}
}

