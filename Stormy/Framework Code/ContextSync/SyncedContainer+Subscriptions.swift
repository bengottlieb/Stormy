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
			completionQueue.suspend()
			Stormy.instance.setupSubscription(in: db) { error in
				if error != nil { finalError = error }
				completionQueue.resume()
			}
		}
		
		completionQueue.async {
			completion(finalError)
		}
	}

}
