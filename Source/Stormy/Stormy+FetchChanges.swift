//
//  Stormy+FetchChanges.swift
//  Internal
//
//  Created by Ben Gottlieb on 9/13/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit


@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
extension Stormy {
	public func fetchChanges(in zone: CKRecordZone? = nil, database: CKDatabase.Scope = .private, since tokenData: Data? = nil, fetching fields: [CKRecord.FieldKey]? = nil, completion: @escaping (Result<FetchedChanges, Error>) -> Void) {
		
		Stormy.instance.startLongRunningTask()
		Stormy.instance.queue {
			guard let zone = zone ?? Stormy.instance.recordZones.first else {
				completion(.failure(StormyError.noAvailableZones))
				Stormy.instance.completeLongRunningTask()
				return
			}
			
			var token: CKServerChangeToken?
			
			if let data = tokenData ?? Stormy.instance.serverFetchTokens[zone.zoneID] {
				if #available(OSXApplicationExtension 10.13, iOS 13.0, iOSApplicationExtension 13.0, *) {
					token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
				} else {
					token = NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
				}
			}
			let op: CKFetchRecordZoneChangesOperation
			
			if #available(OSX 10.14, OSXApplicationExtension 10.14, iOS 12.0, iOSApplicationExtension 12.0, *) {
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
				if let data = token?.data { Stormy.instance.serverFetchTokens[zone.zoneID] = data }
			}
			
			op.fetchRecordZoneChangesCompletionBlock = { err in
				if !Stormy.shouldReturn(after: err, operation: op, in: database, completion: { error in completion(.failure(error ?? err ?? StormyError.unknownError)) }) {
					completion(Result.success(changes))
				}
				Stormy.instance.completeLongRunningTask()
			}
			
			op.recordZoneChangeTokensUpdatedBlock = { zoneID, token, context in
				changes.token = token
			}
			
			Stormy.instance.queue(operation: op, in: database)
		}
	}
}

extension CKServerChangeToken {
	var data: Data? {
		if #available(OSX 10.13, iOS 11.0, *) {
			return try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
		} else {
			return NSKeyedArchiver.archivedData(withRootObject: self)
		}
	}
}
