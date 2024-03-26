//
//  CloudKit+Records.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/18/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit
import Suite

protocol CloudKitIdentifiable { }

extension Stormy {
	public func fetchAll(_ recordType: CKRecord.RecordType, in database: CKDatabase.Scope = .private, matching predicate: NSPredicate = NSPredicate(value: true), limit: Int? = nil, completion: (([CKLocalCache], Error?) -> Void)? = nil) {
		self.startLongRunningTask()
		let query = CKQuery(recordType: recordType, predicate: predicate)
		let op = CKQueryOperation(query: query)
		var results: [CKLocalCache] = []
		
		if let resultsLimit = limit { op.resultsLimit = resultsLimit }
		op.recordFetchedBlock = { record in
			if let cache = database.cache.fetch(record: record) { results.append(cache) }
		}
		op.queryCompletionBlock = { cursor, error in
			if Stormy.shouldReturn(after: error, operation: op, in: database, completion: { err in completion?([], err) }) { return }
			if let cur = cursor {
				self.queue(operation: CKQueryOperation(cursor: cur), in: database)
			} else {
				completion?(results, error)
			}
			self.completeLongRunningTask()
		}
		self.queue(operation: op, in: database)
	}
	
	public func fetchOne(_ recordType: CKRecord.RecordType, in database: CKDatabase.Scope = .private, matching predicate: NSPredicate = NSPredicate(value: true), completion: (([CKLocalCache], Error?) -> Void)? = nil) {
		self.fetchAll(recordType, in: database, matching: predicate, limit: 1, completion: completion)
	}
	
	@available(iOS 15.0, *)
	public func fetch(_ id: CKRecord.ID? = nil, ids: [CKRecord.ID] = [], in database: CKDatabase.Scope = .private, completion: (([CKLocalCache], Error?) -> Void)? = nil) {
		if id == nil && ids.count == 0 { completion?([], nil); return }
		self.startLongRunningTask()
		var idsToFetch = ids
		if let id = id { idsToFetch.append(id) }
		var foundRecords: ThreadsafeArray<CKRecord> = []
		
		let op = CKFetchRecordsOperation(recordIDs: idsToFetch)
		
		op.perRecordResultBlock = { recordID, result in
			switch result {
			case .failure(let error):
				print("Failed to fetch \(recordID): \(error)")
				
			case .success(let record):
				foundRecords.append(record)
			}
		}
		
		op.fetchRecordsResultBlock = { result in
			switch result {
			case .failure(let error):
				if Stormy.shouldReturn(after: error, operation: op, in: database, completion: { err in completion?([], err) }) { return }
				
			case .success:
				let found = foundRecords.compactMap { database.cache.fetch(record: $0) }
				completion?(found, nil)
			}
			self.completeLongRunningTask()
		}
		Stormy.instance.queue(operation: op, in: database)

	}
}

