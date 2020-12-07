//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

public struct SecureBookmark: Identifiable, Codable {
	enum CodingKeys: String, CodingKey {
		case id
		case bookmarkData = "bookmarkData"
		case options = "options"
	}

	public let id: String
	let bookmarkData: Data
	let options: UInt

	public init(id: String, bookmarkData: Data, options: UInt) {
		self.id = id
		self.bookmarkData = bookmarkData
		self.options = options
	}
}
