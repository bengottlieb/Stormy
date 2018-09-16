//
//  CKCopyableOperation.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/20/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

protocol CKCopyableOperation {
	func copy() -> CKOperation?
}

extension Stormy {
	static func shouldReturn(after: Error?, operation: CKCopyableOperation, in db: DatabaseType? = nil, completion: ((Error?) -> Void)? = nil) -> Bool {
		guard let error = after else { return false }			// no error
		
		guard var ckError = error as? CKError else {
			completion?(error)
			return true
		}
		
		if ckError.code == .partialFailure, let root = error.rootCKError { ckError = root }
		
		if ckError.code == .notAuthenticated {
			Stormy.instance.authenticationState = (Stormy.instance.authenticationState == .signingIn) ? .tokenFailed : .notLoggedIn
			return false
		}
		
		if let retry = ckError.retryAfterSeconds, let dupeOp = operation.copy() {
			DispatchQueue.main.asyncAfter(deadline: .now() + retry) {
				if let op = dupeOp as? CKDatabaseOperation, let db = db {
					Stormy.instance.queue(operation: op, in: db)
				} else {
					Stormy.instance.queue(operation: dupeOp)
				}
			}
			return true
		}
		
		return false
	}
}

extension CKModifyRecordZonesOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		let op = CKModifyRecordZonesOperation(recordZonesToSave: self.recordZonesToSave, recordZoneIDsToDelete: self.recordZoneIDsToDelete)
		
		op.modifyRecordZonesCompletionBlock = self.modifyRecordZonesCompletionBlock
		return op
	}
}

@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension CKFetchRecordZoneChangesOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		if #available(OSXApplicationExtension 10.14, iOS 12.0, *) {
			let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: self.recordZoneIDs ?? [], configurationsByRecordZoneID:  self.configurationsByRecordZoneID)
			
			op.fetchRecordZoneChangesCompletionBlock = self.fetchRecordZoneChangesCompletionBlock
			op.recordChangedBlock = self.recordChangedBlock
			op.recordWithIDWasDeletedBlock = self.recordWithIDWasDeletedBlock
			op.recordZoneChangeTokensUpdatedBlock = self.recordZoneChangeTokensUpdatedBlock
			
			return op
		} else {
			return nil
		}
	}
}

extension CKModifySubscriptionsOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		let op = CKModifySubscriptionsOperation(subscriptionsToSave: self.subscriptionsToSave, subscriptionIDsToDelete: self.subscriptionIDsToDelete)
		op.modifySubscriptionsCompletionBlock = self.modifySubscriptionsCompletionBlock
		return op
	}
}

extension CKFetchSubscriptionsOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		guard let subs = self.subscriptionIDs else { return nil }
		let op = CKFetchSubscriptionsOperation(subscriptionIDs: subs)
		op.fetchSubscriptionCompletionBlock = self.fetchSubscriptionCompletionBlock
		return op
	}
}

extension CKQueryOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		let op: CKQueryOperation
		
		if let cursor = self.cursor { op = CKQueryOperation(cursor: cursor) }
		else if let query = self.query { op = CKQueryOperation(query: query) }
		else { return nil }
		
		op.recordFetchedBlock = self.recordFetchedBlock
		op.queryCompletionBlock = self.queryCompletionBlock
		return op
	}
}

extension CKFetchRecordsOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		guard let ids = self.recordIDs else { return nil }
		
		let op = CKFetchRecordsOperation(recordIDs: ids)
		op.fetchRecordsCompletionBlock = self.fetchRecordsCompletionBlock
		op.perRecordCompletionBlock = self.perRecordCompletionBlock
		op.perRecordProgressBlock = self.perRecordProgressBlock
		op.desiredKeys = self.desiredKeys
		
		return op
	}
}

extension CKModifyRecordsOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		let op = CKModifyRecordsOperation(recordsToSave: self.recordsToSave, recordIDsToDelete: self.recordIDsToDelete)
		
		op.clientChangeTokenData = self.clientChangeTokenData
		op.modifyRecordsCompletionBlock = self.modifyRecordsCompletionBlock
		op.perRecordCompletionBlock = self.perRecordCompletionBlock
		op.perRecordProgressBlock = self.perRecordProgressBlock
		return op
	}
}

@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension CKFetchShareMetadataOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		guard let urls = self.shareURLs else { return nil }
		let op = CKFetchShareMetadataOperation(shareURLs: urls)
		
		op.fetchShareMetadataCompletionBlock = self.fetchShareMetadataCompletionBlock
		op.perShareMetadataBlock = self.perShareMetadataBlock
		op.rootRecordDesiredKeys = self.rootRecordDesiredKeys
		op.shouldFetchRootRecord = self.shouldFetchRootRecord
		
		return op
	}
}

@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension CKAcceptSharesOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		guard let metadatas = self.shareMetadatas else { return nil }
		
		let op = CKAcceptSharesOperation(shareMetadatas: metadatas)
		op.acceptSharesCompletionBlock = self.acceptSharesCompletionBlock
		op.perShareCompletionBlock = self.perShareCompletionBlock
		return op
	}
}

@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension CKFetchShareParticipantsOperation: CKCopyableOperation {
	func copy() -> CKOperation? {
		guard let infos = self.userIdentityLookupInfos else { return nil }
		let op = CKFetchShareParticipantsOperation(userIdentityLookupInfos: infos)
		
		op.fetchShareParticipantsCompletionBlock = self.fetchShareParticipantsCompletionBlock
		op.shareParticipantFetchedBlock = self.shareParticipantFetchedBlock
		
		return op
	}
}
