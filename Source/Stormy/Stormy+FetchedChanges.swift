//
//  Stormy+FetchedChanges.swift
//  Stormy_iOS
//
//  Created by Ben Gottlieb on 4/12/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

import Foundation
import CloudKit

extension Stormy {
	public struct FetchedChanges {
		let semaphore = DispatchSemaphore(value: 1)
		public var records: [CKLocalCache] = []
		public var deletedIDs: [CKRecord.ID] = []
		public var tokenData: Data?
		
		init() { }
		
		
		mutating func add(_ record: CKLocalCache?) {
			if let record = record { self.serialize({ self.records.append(record) }) }
		}
		
		func serialize(_ block: () -> Void) {
			self.semaphore.wait()
			block()
			self.semaphore.signal()
		}
		
		var token: CKServerChangeToken? {
			get { return nil }
			set { self.tokenData = newValue?.data }
		}
	}
}
