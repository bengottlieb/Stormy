//
//  AppDelegate.swift
//  iOSTestingHarness
//
//  Created by Ben Gottlieb on 8/16/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import UIKit
import Stormy
import CloudKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?

	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		application.registerForRemoteNotifications()
		
		Stormy.instance.setup(identifier: "iCloud.com.standalone.zap", zones: ["test_zone"])
		
		
		
		let tokenData = UserDefaults.standard.data(forKey: "changeToken")
		Stormy.instance.fetchChanges(since: tokenData) { changes, error in
			if let err = error {
				print("Error fetching: \(err)")
			}
			
			if let chg = changes {
				print("Changes: \(chg.records.count)")
				if let data = changes?.tokenData {
					UserDefaults.standard.set(data, forKey: "changeToken")
				}
			}
		}
		
		Stormy.instance.queue {
			print("Stormy.instance.userRecordID: \(Stormy.instance.userRecordID!)")
		}
		
		//		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
		//			if let error = error { print("Error while registering for notifications: \(error)") }
		//		}
		
		Stormy.instance.setupSubscription(in: .private) { error in
			if let err = error { print("Error setting up on private: \(err)") }
		}
		
		Stormy.instance.setupSubscription(in: .shared) { error in
			if let err = error { print("Error setting up on shared: \(err)") }
		}

		return true
	}

	public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		
		let note = CKDatabaseNotification(fromRemoteNotificationDictionary: userInfo)
		print("Note: \(note)")
		
		completionHandler(.newData)
	}

}

