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
		Stormy.instance.fetchChanges(since: tokenData) { result in
			switch result {
			case .failure(let err):
				print("Error fetching: \(err)")
				
			case .success(let changes):
				print("Changes: \(changes.records.count)")
				if let data = changes.tokenData {
					UserDefaults.standard.set(data, forKey: "changeToken")
				}
			}
		}
		
		Stormy.instance.queue {
			print("Stormy.instance.userRecordID: \(Stormy.instance.userRecordID?.description ?? "--")")
		}
		
		//		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
		//			if let error = error { print("Error while registering for notifications: \(error)") }
		//		}
		
		Stormy.instance.setupSubscription(in: .private) { error in
			if let err = error, !err.isDuplicateSubscriptionError { print("Error setting up on private: \(err)") }
		}
		
		Stormy.instance.setupSubscription(in: .shared) { error in
			if let err = error, !err.isDuplicateSubscriptionError { print("Error setting up on shared: \(err)") }
		}

		return true
	}

	public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		
		if Stormy.instance.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler) { return }
		
		completionHandler(.noData)
	}

}

