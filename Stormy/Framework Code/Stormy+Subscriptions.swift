//
//  Stormy+Subscriptions.swift
//  Zap2
//
//  Created by Ben Gottlieb on 9/15/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit


@available(OSXApplicationExtension 10.12, iOSApplicationExtension 10.0, *)
extension Stormy {
	
	func subscriptionID(in dbType: DatabaseType, on recordName: CKRecord.RecordType?, forZone: CKRecordZone? = nil) -> String? {
		if dbType == .shared {
			return "shared-subscription"
		}
		if let name = recordName {
			return "\(dbType.rawValue)-\(name)-subscription"
		} else if let zone = forZone {
			return "\(dbType.rawValue)-\(zone)-(all)-subscription"
		} else {
			return "\(dbType.rawValue)-(all)-subscription"
		}
	}
	public func setupSubscription(in dbType: DatabaseType, on recordName: CKRecord.RecordType? = nil, forZone: CKRecordZone? = nil, predicate: NSPredicate = NSPredicate(value: true), options: CKQuerySubscription.Options = [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion], completion: ((Error?) -> Void)?) {
		
		#if targetEnvironment(simulator)
			completion?(SubscriptionError.noSubscriptionsOnTheSimulator)
			if recordName == nil || recordName != nil { return }
		#endif
		
		guard let id = self.subscriptionID(in: dbType, on: recordName, forZone: forZone) else {
			completion?(Stormy.StorymError.needAZoneOrRecordType)
			return
		}
		
		let fetchOp = CKFetchSubscriptionsOperation.fetchAllSubscriptionsOperation()
		fetchOp.fetchSubscriptionCompletionBlock = { subs, error in
			if Stormy.shouldReturn(after: error, operation: fetchOp, in: dbType, completion: completion) { return }
			
			if subs?[id] != nil {	//already created
				print(subs!)
				completion?(nil)
				return
			}
			
			let sub: CKSubscription
			
			if dbType == .shared {
				sub = CKDatabaseSubscription(subscriptionID: id)
				(sub as? CKDatabaseSubscription)?.recordType = recordName
			} else if let name = recordName {
				sub = CKQuerySubscription(recordType: name, predicate: predicate, subscriptionID: id, options: options)
			} else if let zoneID = forZone?.zoneID {
				sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: id)
			} else {
				sub = CKDatabaseSubscription(subscriptionID: id)
//				completion?(SubscriptionError.needAZoneOrRecordType)
//				return
			}
			let noteInfo = CKSubscription.NotificationInfo()
			
			noteInfo.shouldSendContentAvailable = true
			sub.notificationInfo = noteInfo

			let subscribeOp = CKModifySubscriptionsOperation(subscriptionsToSave: [sub], subscriptionIDsToDelete: nil)
			subscribeOp.modifySubscriptionsCompletionBlock = { added, removed, error in
				if Stormy.shouldReturn(after: error, operation: subscribeOp, in: dbType, completion: completion) { return }
				completion?(error)
			}
			Stormy.instance.queue(operation: subscribeOp, in: dbType)
		}
		Stormy.instance.queue(operation: fetchOp, in: dbType)
	}
	
}
