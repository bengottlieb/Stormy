//
//  SyncedContainer+Subscriptions.swift
//  ContextSync
//
//  Created by Ben Gottlieb on 11/13/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

#if canImport(UIKit)
import UIKit

@available(OSX 10.12, OSXApplicationExtension 10.12, iOS 10.0, iOSApplicationExtension 10.0, *)
extension SyncedContainer {
	public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
		print("Received note: \(CKDatabaseNotification(fromRemoteNotificationDictionary: userInfo)!.description)")
		self.pullChanges() {
			completionHandler(.newData)
		}
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
#endif
