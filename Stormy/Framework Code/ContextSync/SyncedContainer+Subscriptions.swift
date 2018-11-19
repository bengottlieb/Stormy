//
//  SyncedContainer+Subscriptions.swift
//  ContextSync
//
//  Created by Ben Gottlieb on 11/13/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

@available(iOSApplicationExtension 10.0, *)
@available(OSXApplicationExtension 10.12, *)
extension DatabaseType {
	var subscriptionDefaultsKey: String {
		let subscriptionsCreatedDefaultsKey = SyncedContainer.defaultsPrefix + "subscriptions-created-on-" + self.rawValue
		return subscriptionsCreatedDefaultsKey
	}

	var subscriptionID: String {
		return self.rawValue + "-subscription"
	}
}

@available(iOSApplicationExtension 10.0, *)
extension SyncedContainer {
	public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
		let note = CKDatabaseNotification(fromRemoteNotificationDictionary: userInfo)
		print("Received note: \(note)")
		self.pullChanges()
		completionHandler(.newData)
		return true
	}
	
	func setupSubscriptions(on dbs: [DatabaseType], completion: @escaping (Error?) -> Void) {
		var finalError: Error?
		let completionQueue = DispatchQueue(label: "subscription setup")
		
		for db in dbs {
			if SyncedContainer.userDefaults.bool(forKey: db.subscriptionDefaultsKey) {
				continue
			}

			let sub = CKDatabaseSubscription(subscriptionID: db.subscriptionID)
			let noteInfo = CKSubscription.NotificationInfo()
			
			noteInfo.shouldSendContentAvailable = true
			sub.notificationInfo = noteInfo
			
			completionQueue.suspend()
			
			let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [sub], subscriptionIDsToDelete: nil)
			operation.modifySubscriptionsCompletionBlock = { created, deleted, error in
				if created?.first != nil {
					SyncedContainer.userDefaults.set(true, forKey: db.subscriptionDefaultsKey)
					print("Created subscription on \(db): \(sub.subscriptionID)")
				} else if let err = error, err._code == 2, err._domain == "CKErrorDomain" {	// already exists
					SyncedContainer.userDefaults.set(true, forKey: db.subscriptionDefaultsKey)
				} else if let err = error {
					finalError = err
				}
				completionQueue.resume()
			}
		
			Stormy.instance.queue(operation: operation, in: db)
		}
		
		completionQueue.async {
			completion(finalError)
		}
	}

}
