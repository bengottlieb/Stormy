//
//  URL+Stormy.swift
//  Stormy
//
//  Created by Ben Gottlieb on 9/21/18.
//  Copyright © 2018 Stand Alone, inc. All rights reserved.
//

import Foundation

extension URL {
	func isSameFile(as other: URL) -> Bool {
		do {
			if self.path == other.path { return true }
			let myAttr = try FileManager.default.attributesOfItem(atPath: self.path)
			let theirAttr = try FileManager.default.attributesOfItem(atPath: other.path)
			let mySize = myAttr[.size] as? UInt64 ?? UInt64.max - 1
			let theirSize = theirAttr[.size] as? UInt64 ?? UInt64.max - 2

			if mySize != theirSize { return false }
			
			let myData = try Data(contentsOf: self, options: .mappedRead)
			let theirData = try Data(contentsOf: other, options: .mappedRead)
			var offset: UInt64 = 0
			let chunkSize: UInt64 = 1024 * 256
			
			
			while offset < mySize {
				if !autoreleasepool() { () -> Bool in
					let thisChunkSize = min(chunkSize, mySize - offset)
					
					let myChunk = myData[offset..<(offset + thisChunkSize)]
					let theirChunk = theirData[offset..<(offset + thisChunkSize)]
					
					let myMD5 = myChunk.md5
					let theirMD5 = theirChunk.md5
					offset += chunkSize

					return myMD5 == theirMD5
				} { return false }
			}
			
			return true
		} catch {
			print("Error while checking files")
		}
		return false
	}
}
