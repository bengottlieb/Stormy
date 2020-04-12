//
//  Stormy+RemoteNotifications.swift
//  Stormy_iOS
//
//  Created by Ben Gottlieb on 4/12/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

import Foundation
import CloudKit

@available(iOSApplicationExtension 10.0, *)
public extension Stormy {
	func received(remoteNotification info: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
		guard let note = CKNotification(fromRemoteNotificationDictionary: info) else { return false }
		
		if let dbNote = note as? CKDatabaseNotification {
			Stormy.instance.fetchChanges(database: dbNote.databaseScope) { changes, error in
				
				completion(.newData)
			}
		}
		
		return true
	}
}
