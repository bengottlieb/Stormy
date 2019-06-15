//
//  CKRecord.ID+Stormy.swift
//  Stormy
//
//  Created by Ben Gottlieb on 11/5/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Foundation
import CloudKit

extension CKRecord.ID {
	public var typeName: String? {
		if let sep = Stormy.instance.recordIDTypeSeparator {
			let comp = self.recordName.components(separatedBy: sep)
			if comp.count == 2 { return comp.first }
		}
		return nil
	}
	
	public var recordID: String? {
		if let sep = Stormy.instance.recordIDTypeSeparator {
			let comp = self.recordName.components(separatedBy: sep)
			if comp.count == 2 { return comp.last }
		}
		return nil
	}
	
	public convenience init(recordName: String, typeName: String, zoneID: CKRecordZone.ID? = nil) {
		var name = recordName
		if let sep = Stormy.instance.recordIDTypeSeparator { name = typeName + sep + recordName }
		
		if let zone = zoneID {
			self.init(recordName: name, zoneID: zone)
		} else {
			self.init(recordName: name)
		}
	}
}
