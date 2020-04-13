//
//  MenuItem.swift
//  iOSTestingHarness
//
//  Created by Ben Gottlieb on 4/12/20.
//  Copyright © 2020 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreData
import Stormy

class MenuItem: SyncableManagedObject {
	override class var parentRelationshipName: String? { return "menu" }
}
