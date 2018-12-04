//
//  CKLocalCache+Share.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/19/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension Stormy {
	public func acceptShare(url: URL?, completion: ((Error?) -> Void)?) {
		guard let url = url else { completion?(Stormy.StormyError.shareMissingURL); return }
		let metadataFetchOp = CKFetchShareMetadataOperation(shareURLs: [url])
		metadataFetchOp.perShareMetadataBlock = { url, metadata, error in
			if Stormy.shouldReturn(after: error, operation: metadataFetchOp, completion: completion) { return }
			guard let meta = metadata else {
				completion?(error)
				return
			}
			self.acceptShare(metadata: meta, completion: completion)
		}
		
		self.queue(operation: metadataFetchOp)
	}
	
	public func acceptShare(metadata: CKShare.Metadata, completion: ((Error?) -> Void)?) {
		let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
		op.perShareCompletionBlock = { metadata, share, error in
			if Stormy.shouldReturn(after: error, operation: op, completion: completion) { return }
			completion?(error)
		}
		
		self.queue(operation: op)
	}
}

@available(OSXApplicationExtension 10.12, iOS 10.0, *)
extension CKLocalCache {
	public func share(with userID: CKRecord.ID, completion: ((URL?, Error?) -> Void)? = nil) {
		if self.database != .private { completion?(nil, Stormy.StormyError.sharesMustBePrivate); return }
		if self.recordZone == nil { completion?(nil, Stormy.StormyError.sharesMustHaveNonDefaultZone); return }
		
		guard let record = self.originalRecord else {
			self.save() { error in
				if error != nil || !self.existsOnServer { completion?(nil, error) } else { self.share(with: userID, completion: completion) }
			}
			return
		}
		
		let share = CKShare(rootRecord: record)

		let fetchParticipantOp = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [CKUserIdentity.LookupInfo(userRecordID: userID)])
		fetchParticipantOp.shareParticipantFetchedBlock = { participant in
			participant.permission = .readWrite
			share.addParticipant(participant)
		}
		
		Stormy.instance.startLongRunningTask()
		fetchParticipantOp.fetchShareParticipantsCompletionBlock = { error in
			if Stormy.shouldReturn(after: error, operation: fetchParticipantOp, completion: { err in completion?(nil, err) }) { return }
			if error != nil || share.participants.count == 0 {
				completion?(nil, error ?? Stormy.StormyError.shareFailedToFindParticipants)
				Stormy.instance.completeLongRunningTask()
				return
			}
			
			let op = CKModifyRecordsOperation(recordsToSave: [share, record], recordIDsToDelete: nil)
			op.modifyRecordsCompletionBlock = { records, ids, error in
				if Stormy.shouldReturn(after: error, operation: op, completion: { err in completion?(nil, err) }) { return }
				completion?(share.url, error)
				Stormy.instance.completeLongRunningTask()
			}
			Stormy.instance.queue(operation: op, in: .private)
		}
		
		Stormy.instance.queue(operation: fetchParticipantOp)
	}
	
	public func unshare(with userID: CKRecord.ID, completion: ((Error?) -> Void)? = nil) {
		guard self.database == .private, self.recordZone != nil else { completion?(nil); return }		// not shared, we're done
		
		guard let record = self.originalRecord else {
			self.reloadFromServer() { error in
				if error != nil || !self.existsOnServer { completion?(error); return }
				self.unshare(with: userID, completion: completion)
			}
			return
		}
		
		let share = CKShare(rootRecord: record)
		
		Stormy.instance.startLongRunningTask()
		let fetchParticipantOp = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [CKUserIdentity.LookupInfo(userRecordID: userID)])
		fetchParticipantOp.shareParticipantFetchedBlock = { participant in
			participant.permission = .readWrite
			share.removeParticipant(participant)
		}
		
		fetchParticipantOp.fetchShareParticipantsCompletionBlock = { error in
			if Stormy.shouldReturn(after: error, operation: fetchParticipantOp, completion: { err in completion?(err) }) { return }
			if error != nil || share.participants.count == 0 {
				completion?(error ?? Stormy.StormyError.shareFailedToFindParticipants)
				Stormy.instance.completeLongRunningTask()
				return
			}
			
			let op = CKModifyRecordsOperation(recordsToSave: [share, record], recordIDsToDelete: nil)
			op.modifyRecordsCompletionBlock = { records, ids, error in
				if !Stormy.shouldReturn(after: error, operation: op, completion: { err in completion?(err) }) {
					completion?(error)
				}
				Stormy.instance.completeLongRunningTask()
			}
			Stormy.instance.queue(operation: op, in: .private)
		}
		
		Stormy.instance.queue(operation: fetchParticipantOp)
	}
}
