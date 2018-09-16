//
//  ViewController.swift
//  iOSTestingHarness
//
//  Created by Ben Gottlieb on 8/16/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import UIKit
import Stormy

class ViewController: UIViewController {
	@IBOutlet var tableView: UITableView!

	override func viewDidLoad() {
		super.viewDidLoad()
	}


}

extension ViewController: UITableViewDataSource {
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.devices.count
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
		
		cell.textLabel?.text = "\(self.devices[indexPath.row].displayName) - \(self.devices[indexPath.row].state)"
		return cell
	}
}

