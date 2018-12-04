//
//  Stormy+FetchChanges.swift
//  Internal
//
//  Created by Ben Gottlieb on 9/13/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit


@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension Stormy {
	public func fetchChanges(in zone: CKRecordZone? = nil, database: DatabaseType = .private, since tokenData: Data? = nil, fetching fields: [CKRecord.FieldKey]? = nil, completion: @escaping (FetchedChanges?, Error?) -> Void) {
		
		Stormy.instance.startLongRunningTask()
		Stormy.instance.queue {
			guard let zone = zone ?? Stormy.instance.recordZones.first else {
				completion(nil, nil)
				Stormy.instance.completeLongRunningTask()
				return
			}
			let token: CKServerChangeToken? = (tokenData != nil) ? NSKeyedUnarchiver.unarchiveObject(with: tokenData!) as? CKServerChangeToken : nil
			let op: CKFetchRecordZoneChangesOperation
			
			if #available(OSXApplicationExtension 10.14, iOS 12.0, *) {
				let config = [zone.zoneID: CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: token, resultsLimit: nil, desiredKeys: fields)]
				op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone.zoneID], configurationsByRecordZoneID: config)
			} else {
				let options = [zone.zoneID: CKFetchRecordZoneChangesOperation.ZoneOptions()]
				op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone.zoneID], optionsByRecordZoneID: options)
			}
			var changes = FetchedChanges()
			
			op.recordChangedBlock = { record in
				changes.add(database.cache.fetch(record: record))
			}
			
			op.recordWithIDWasDeletedBlock = { id, type in
				changes.serialize { changes.deletedIDs.append(id) }
			}
			
			op.recordZoneFetchCompletionBlock = { id, token, data, _, error in
				changes.token = token
			}
			
			op.fetchRecordZoneChangesCompletionBlock = { err in
				if !Stormy.shouldReturn(after: err, operation: op, in: database, completion: { err in completion(nil, err) }) {
					completion(changes, nil)
				}
				Stormy.instance.completeLongRunningTask()
			}
			
			op.recordZoneChangeTokensUpdatedBlock = { zoneID, token, context in
				changes.token = token
			}
			
			Stormy.instance.queue(operation: op, in: database)
		}
	}
	
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
			set {
				if let token = newValue {
					if #available(OSXApplicationExtension 10.13, iOSApplicationExtension 11.0, *) {
						self.tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
					} else {
						self.tokenData = NSKeyedArchiver.archivedData(withRootObject: token)
					}
				}
			}
		}
	}
}
