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
import Studio
import CoreData

class ViewController: UIViewController {
	@IBOutlet var restaurantNameField: UITextField!
	@IBOutlet var menuItemNameField: UITextField!
	@IBOutlet var menuItemPriceField: UITextField!

	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
	}
	
	var context: NSManagedObjectContext { return SyncedContainer.instance.container.viewContext }
	
	var menu: Menu? {
		guard let name = self.restaurantNameField.text, !name.isEmpty else { return nil }
		if let existing: Menu = context.fetchAny(matching: NSPredicate(format: "restaurantName == %@", name)) { return existing }
		return nil
	}
	
	@IBAction func createOrFetchRestaurant() {
		guard self.menu == nil, let name = self.restaurantNameField.text, !name.isEmpty else { return }
		
		let menu: Menu = context.insertObject()
		
		menu.restaurantName = name
		menu.sync()
		
	}
	
	@IBAction func createOrFetchMenuItem() {
		guard let menu = self.menu, let itemName = self.menuItemNameField.text, !itemName.isEmpty else { return }
		let price = Double(self.menuItemPriceField.text ?? "") ?? 0
		
		if let items = menu.menuItems as? Set<MenuItem>, let existing = items.first(where: { $0.name == itemName }) {
			existing.price = price
			existing.sync()
		} else {
			let menuItem: MenuItem = context.insertObject()

			menuItem.menu = menu
			menuItem.name = itemName
			menuItem.price = price
			menuItem.sync()

		}
	}
	
	@IBAction func acceptShare() {
		let url = URL(string: "https://www.icloud.com/share/0ob2iEeP6L-ZRGvLnZPFk8Emg")!
		Stormy.instance.acceptShare(url: url) { error in
			if let err = error { print("error accepting a share: \(err)") }
		}
	}

	var record = CKDatabase.Scope.public.cache.fetch(type: "TEST_RECORD", id: CKRecord.ID(recordName: "EDITING RECORD"))
	lazy var privateRecord: CKLocalCache = { CKDatabase.Scope.private.cache.fetch(type: "TEST_PRIVATE_RECORD", id: CKRecord.ID(recordName: "EDITING_PRIVATE RECORD", zoneID: Stormy.instance.recordZones.first!.zoneID)) }()

	@IBAction func editRecord() {
		self.record.reloadFromServer(andThenSave: true) { err in
			if let error = err {
				print("Error when fetching record: \(error)")
			}
		}
	}

	@IBAction func shareRecord() {
		self.privateRecord.fetchShareURL { url, error in
			if let url = url {
				print("Fetched share URL: \(url)")
			} else if let err = error {
				print("Error when fetching share URL: \(err)")
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
		let recordID = CKRecord.ID(recordName: "PARENT - RECORD", zoneID: Stormy.instance.recordZones.first!.zoneID)
		let record = CKDatabase.Scope.private.cache.fetch(type: "PARENT_RECORD", id: recordID)

		record.reloadFromServer { error in
			let childID = CKRecord.ID(recordName: "CHILD - \(Int(Date().timeIntervalSinceReferenceDate) % 100000)", zoneID: Stormy.instance.recordZones.first!.zoneID)
			let child = CKDatabase.Scope.private.cache.fetch(type: "CHILD_RECORD", id: childID)
			child["c_value"] = Int16.random(in: 0...1000)
			child.setParent(record)
		
			record["p_value"] = Int16.random(in: 0...1000)
			record.save(reloadingFirst: false) { error in
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
}

