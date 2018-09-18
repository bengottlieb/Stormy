//
//  ViewController.swift
//  iOSTestingHarness
//
//  Created by Ben Gottlieb on 8/16/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import UIKit
import Stormy
import CloudKit

class ViewController: UIViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
	}
	
	
	
	@IBAction func acceptShare() {
		let url = URL(string: "https://www.icloud.com/share/0ob2iEeP6L-ZRGvLnZPFk8Emg")!
		Stormy.instance.acceptShare(url: url) { error in
			if let err = error { print("error accepting a share: \(err)") }
		}
	}

	var record = CKRecord.Cache(type: "TEST_RECORD", id: CKRecord.ID(recordName: "EDITING RECORD"), in: .public)
	
	@IBAction func editRecord() {
		self.record.reloadFromServer(andThenSave: true) { err in
			if let error = err {
				print("Error when fetching record: \(error)")
			}
		}
	}
	
	@IBAction func stopEditingRecord() {
		self.record["value"] = Int16.random(in: 0...1000)
		if self.record["value2"] == nil {
			self.record["value2"] = Int16.random(in: 0...1000)
		}
		self.record.save(reloadingFirst: false) { error in
			if let error = error { print("Error when saving: \(error)") }
		}
	}
	
	@IBAction func addRecord() {
		let recordID = CKRecord.ID(recordName: Date().description, zoneID: Stormy.instance.recordZones.first!.zoneID)
		let record = CKRecord.Cache(type: "TEST_RECORD", id: recordID, in: .private)
		
		record["value"] = Int16.random(in: 0...1000)
		record.save() { error in
			if let err = error {
				print("Error: \(err)")
			} else {
//				let userID = CKRecord.ID(recordName: "_e99701a62ea25fe2cdabc3e914563b6f")
//				record.share(with: userID, completion: { url, error in
//					if let error = error { print("Error while saving: \(error)") }
//					print("URL: \(url?.absoluteString ?? "--")")
//				})
			}
		}
	}
}

