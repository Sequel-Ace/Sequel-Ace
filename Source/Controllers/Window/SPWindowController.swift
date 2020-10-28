//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 28.10.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

@objc extension SPWindowController {
	open override func perform(_ aSelector: Selector) -> Unmanaged<AnyObject>? {
		if let response = super.perform(aSelector) {
			return response
		}
		if !selectedTableDocument.responds(to: aSelector) {
			doesNotRecognizeSelector(aSelector)
		}
		return selectedTableDocument.perform(aSelector)
	}

	open override func perform(_ aSelector: Selector, with object: Any?) -> Unmanaged<AnyObject>? {
		if let response = super.perform(aSelector, with: object) {
			return response
		}
		guard let selectedDocument = selectedTableDocument else {
			doesNotRecognizeSelector(aSelector)
			return nil
		}
		if !selectedDocument.responds(to: aSelector) {
			doesNotRecognizeSelector(aSelector)
		}
		return selectedDocument.perform(aSelector, with: object)
	}
}
