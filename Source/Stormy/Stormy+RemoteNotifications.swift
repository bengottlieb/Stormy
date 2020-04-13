//
//  Stormy+RemoteNotifications.swift
//  Stormy_iOS
//
//  Created by Ben Gottlieb on 4/12/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import Foundation
import CloudKit

@available(iOSApplicationExtension 10.0, *)
public extension Stormy {
	func application(_ application: UIApplication, didReceiveRemoteNotification info: [AnyHashable : Any], fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
		guard let note = CKNotification(fromRemoteNotificationDictionary: info) else { return false }
		
		if let dbNote = note as? CKDatabaseNotification {
			Stormy.instance.fetchChanges(database: dbNote.databaseScope) { result in
				switch result {
				case .success(let changes):
					print("Got changes: \(changes)")
					
				case .failure(let err): print("Error: \(err) when fetching changes in response to a push notification: \n\n\(info)")
				}
				completion(.newData)
			}
		} else {
			return false
		}
		
		return true
	}
}
#endif
