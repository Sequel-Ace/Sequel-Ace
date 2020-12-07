//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

//public struct SecureBookmark: Identifiable, Codable {
//	enum CodingKeys: String, CodingKey {
//		case id = "theId"
//		case bookmarkData = "theBookmarkData"
//		case options = "theOptions"
//	}
//
//	public let id: String
//	let bookmarkData: Data
//	let options: UInt
//
//	public init(id: String, bookmarkData: Data, options: UInt) {
//		self.id = id
//		self.bookmarkData = bookmarkData
//		self.options = options
//	}
//}

struct SecureBookmark: Encodable, Decodable {
	
	let id: String
	let bookmarkData: String
	let options: UInt
}


//
//public struct SecureBookmark: Codable {
//
//	let id: String
//	let bookmarkData: Data
//	let options: UInt
//
//	
//}
