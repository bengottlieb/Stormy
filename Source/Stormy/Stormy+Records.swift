//
//  CloudKit+Records.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/18/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

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
	
	public func fetch(_ id: CKRecord.ID? = nil, ids: [CKRecord.ID] = [], in database: CKDatabase.Scope = .private, completion: (([CKLocalCache], Error?) -> Void)? = nil) {
		if id == nil && ids.count == 0 { completion?([], nil); return }
		self.startLongRunningTask()
		var idsToFetch = ids
		if let id = id { idsToFetch.append(id) }
		
		let op = CKFetchRecordsOperation(recordIDs: idsToFetch)
		op.fetchRecordsCompletionBlock = { results, error in
			if Stormy.shouldReturn(after: error, operation: op, in: database, completion: { err in completion?([], err) }) { return }
			if let values = results?.values {
				let found = Array(values).compactMap { database.cache.fetch(record: $0) }
				completion?(found, error)
			} else {
				completion?([], error)
			}
			self.completeLongRunningTask()
		}
		Stormy.instance.queue(operation: op, in: database)

	}
}

