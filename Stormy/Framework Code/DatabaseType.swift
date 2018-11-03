//
//  DatabaseType.swift
//  Stormy
//
//  Created by Ben Gottlieb on 11/2/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Foundation
import CloudKit

public enum DatabaseType: String {
	case `public`, `private`, shared

	static var caches: [DatabaseType: Cache] = [:]
	
	public var cache: Cache {
		if let cache = DatabaseType.caches[self] { return cache }
		
		let cache = Cache(type: self)
		DatabaseType.caches[self] = cache
		return cache
	}
}
