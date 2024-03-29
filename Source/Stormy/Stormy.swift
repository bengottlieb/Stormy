//
//  Stormy.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/6/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit
import Suite

#if canImport(UIKit)
import UIKit
#endif

extension CKRecordZone.ID: StringConvertible {
	public var string: String { return self.zoneName }
}

@available(OSX 10.15, iOS 13.0, tvOS 13, watchOS 6, *)
extension Stormy: ObservableObject {
}

extension Stormy {
    func objectChanged() {
        if #available(OSX 10.15, iOS 13.0, tvOS 13, watchOS 6, *) {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}

public class Stormy {
	public struct Notifications {
		static public let availabilityChanged = Notification.Name("stormy-availabilityChanged")
		static public let didFetchCloudKitUserRecordID = Notification.Name("stormy-didFetchCloudKitUserRecordID")
		static public let recordsCreatedViaPush = Notification.Name("stormy-recordsCreatedViaPush")
		static public let recordsModifiedViaPush = Notification.Name("stormy-recordsModifiedViaPush")
		static public let recordsModifiedOrCreatedViaPush = Notification.Name("stormy-recordsModifiedOrCreatedViaPush")
		static public let recordsDeletedViaPush = Notification.Name("stormy-recordsDeletedViaPush")
	}
	
	public static let instance = Stormy()
	public enum AuthenticationState { case notLoggedIn, signingIn, tokenFailed, denied, authenticated }
	
	#if os(iOS)
		public var application: UIApplication?
		var currentBackgroundTaskID = UIBackgroundTaskIdentifier.invalid
	#endif
	public var container: CKContainer!
	public var publicDatabase: CKDatabase!
	public var privateDatabase: CKDatabase!
	public var sharedDatabase: CKDatabase?
	public var containerIdentifer: String!
	public var authenticationState = AuthenticationState.notLoggedIn { didSet {
        if self.authenticationState != oldValue {
            objectChanged()
            if (self.authenticationState == .authenticated || self.authenticationState == .denied) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notifications.availabilityChanged, object: nil)
                }
            }
		}
	}}
	public var isAvailable: Bool { return self.authenticationState == .authenticated }
	public var isUnavailable: Bool { return self.authenticationState == .denied || self.authenticationState == .tokenFailed }
	public var enabled = false
	public var autoFetchZones = true
	public var recordZones: [CKRecordZone] = []
    public var userRecordID: CKRecord.ID? { didSet { objectChanged() }}
	public var recordIDTypeSeparator: String?		// if this is set, a record ID consists of the record name + recordIDTypeSeparator + a unique ID- ex: Book/12356

	public static var serverFetchTokenKey = "stormy_serverFetchTokenData"
	public var serverFetchTokens = UserDefaultsBackedDictionary<CKRecordZone.ID, Data>() { id in Stormy.serverFetchTokenKey + id.string }

	static public var childReferencesFieldName = "child_refs"
	public func resetServerFetchTokens() {
		for zone in Stormy.instance.recordZones {
			serverFetchTokens.removeValue(forKey: zone.zoneID)
		}
	}
	
	private let operationSemaphore = DispatchSemaphore(value: 1)
	private var queuedOperations: [(CKDatabase.Scope, Operation)] = []
	private var longRunningTaskCount = 0
	private var attemptConnection: (() -> Void)?
	
	func startLongRunningTask() {
		self.longRunningTaskCount += 1
		#if os(iOS)
			if self.longRunningTaskCount == 1, let app = self.application {
				self.currentBackgroundTaskID = app.beginBackgroundTask(withName: "Stormy") {
					DispatchQueue.main.async { self.currentBackgroundTaskID = .invalid }
				}
			}
		#endif
	}
	
	func completeLongRunningTask() {
		if self.longRunningTaskCount == 0 { return }
		self.longRunningTaskCount -= 1
		#if os(iOS)
			if self.longRunningTaskCount == 0, self.currentBackgroundTaskID != .invalid {
				let taskID = self.currentBackgroundTaskID
				self.currentBackgroundTaskID = .invalid
				self.application?.endBackgroundTask(taskID)
			}
		#endif
	}
	
	@objc func didBecomeActive() {
        if self.authenticationState != .signingIn, !self.isAvailable { self.attemptConnection?() }
	}
	
    public func setup(identifier: String, zones: [String] = [], andConnect connectNow: Bool = true, andContainer: Bool = false, completion: @escaping (Bool) -> Void) {
		self.containerIdentifer = identifier

		self.container = CKContainer(identifier: self.containerIdentifer)
		self.publicDatabase = self.container.publicCloudDatabase
		self.privateDatabase = self.container.privateCloudDatabase
		if #available(OSX 10.12, iOS 10.0, *) { self.sharedDatabase = self.container.sharedCloudDatabase }

		#if os(iOS)
			NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
		#endif
		
		if self.authenticationState != .notLoggedIn && self.authenticationState != .tokenFailed {
			completion(false)
			return
		}

		self.attemptConnection = { [weak self] in
			guard let self = self, self.authenticationState != .signingIn else {
				completion(false)
				return
			}
			self.authenticationState = .signingIn
			self.container.accountStatus { status, error in
				switch status {
				case .available:
					if !connectNow {
						Stormy.instance.authenticationState = .authenticated
                        if self.isAvailable { self.attemptConnection = nil }
						self.flushQueue()
                        if andContainer {
                            SyncedContainer.instance.setupCloud(identifier: identifier, includingSubscriptions: true, andConnect: connectNow, completion: completion)
                        } else {
                            completion(true)
                        }
						return
					}
					self.setupZones(names: zones) { _ in
						self.container.fetchUserRecordID() { id, err in
							if id != self.userRecordID {
								self.userRecordID = id
								NotificationCenter.default.post(name: Notifications.didFetchCloudKitUserRecordID, object: nil)
							}
							if let error = err { print("Error fetching userRecordID: \(error)") }
							Stormy.instance.authenticationState = (Stormy.instance.authenticationState == .tokenFailed) ? .tokenFailed : .authenticated
                            if self.isAvailable { self.attemptConnection = nil }
							self.flushQueue()
                            if andContainer {
                                SyncedContainer.instance.setupCloud(identifier: identifier, includingSubscriptions: true, andConnect: connectNow, completion: completion)
                            } else {
                                completion(true)
                            }
						}
					}
					
				case .couldNotDetermine: fallthrough
				case .noAccount, .restricted: fallthrough
				default:
					self.authenticationState = .denied
					print("No CloudKit Access.")
					self.flushQueue()
					completion(false)
				}
			}
		}
		self.attemptConnection?()
	}
	
	func flushQueue() {
		self.operationSemaphore.wait()
		let ops = self.queuedOperations
		self.queuedOperations = []
		self.operationSemaphore.signal()
		
		ops.forEach {
			self.queue(operation: $0.1, in: $0.0)
		}
	}
	
	public func database(_ type: CKDatabase.Scope) -> CKDatabase? {
		switch type {
		case .public: return self.publicDatabase
		case .private: return self.privateDatabase
		case .shared: return self.sharedDatabase
		@unknown default: return self.publicDatabase
		}
	}
	
	func setupZones(names: [String], completion: ((Error?) -> Void)? = nil) {
		if names.count == 0 {
			completion?(nil)
			return
		}

		let completeQueue = DispatchQueue(label: "setupZoneQueue")
		completeQueue.suspend()
		
		var combinedError: Error?
		
		completeQueue.async {
			completion?(combinedError)
		}
		
		completeQueue.suspend()
		let zones = names.map { CKRecordZone(zoneName: $0) }
		let op = CKModifyRecordZonesOperation(recordZonesToSave: zones, recordZoneIDsToDelete: nil)
		op.modifyRecordZonesCompletionBlock = { zones, deleted, error in
			defer { completeQueue.resume() }
			if Stormy.shouldReturn(after: error, operation: op, completion: nil) { return }
			self.recordZones = zones ?? []
			if let err = error, combinedError == nil { combinedError = err }
		}
		self.privateDatabase.add(op)
		completeQueue.resume()
	}
	
	public func zone(withID id: CKRecordZone.ID) -> CKRecordZone? {
		for zone in self.recordZones { if zone.zoneID == id { return zone }}
		return nil
	}
	
	public func zone(named name: String) -> CKRecordZone {
		return CKRecordZone(zoneName: name)
	}
	
	public func queue(_ block: @escaping () -> Void) {
		self.queue(operation: BlockOperation(block: block))
	}
	
	public func queue(operation: Operation, in type: CKDatabase.Scope = .public) {
		if self.isAvailable {
			if let ckdOp = operation as? CKDatabaseOperation {
				self.database(type)?.add(ckdOp)
			} else if let ckOp = operation as? CKOperation {
				self.container.add(ckOp)
			} else {
				OperationQueue.main.addOperation(operation)
			}
		} else if self.isUnavailable {
			operation.start()
		} else {
			self.operationSemaphore.wait()
			self.queuedOperations.append((type, operation))
			self.operationSemaphore.signal()
		}
	}
	
}
