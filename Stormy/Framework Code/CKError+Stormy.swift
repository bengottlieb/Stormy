//
//  CKError+Stormy.swift
//  Internal
//
//  Created by Ben Gottlieb on 8/22/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import CloudKit

extension Error {
	public var rootCKError: CKError? {
		guard let ckError = self as? CKError else { return nil }
		if ckError.code == .partialFailure, let byID = ckError.partialErrorsByItemID?.values, let first = byID.first as? CKError {
			return first
		}
		return ckError
	}
}

extension Stormy {
	public enum StormyError: Error { case noSubscriptionsOnTheSimulator, needAZoneOrRecordType, iCloudNotAvailable, shareMissingURL, sharesMustBePrivate, sharesMustHaveNonDefaultZone, shareFailedToFindParticipants, notSignedIn }
}
