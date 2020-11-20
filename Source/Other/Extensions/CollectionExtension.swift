//
//  CollectionExtension.swift
//  sequel-ace
//
//  Created by Jakub Kaspar on 20.11.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

public extension Collection {

	/// Returns the element at the specified index if it is within bounds, otherwise nil.
	subscript (safe index: Index) -> Element? {
		return indices.contains(index) ? self[index] : nil
	}

	/// Returns second element from collection
	var second: Element? {
		return self.dropFirst().first
	}

	var isNotEmpty: Bool {
		return !isEmpty
	}
}

public extension Set {
	var isNotEmpty: Bool {
		return !isEmpty
	}
}
