//
// Created by Luis Aguiniga on 2023.10.14
//  Copyright © 2023 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import OSLog

@objc class SPTableHistoryManager: NSObject {
	typealias Entry = SPTableHistoryEntry
	@objc var countPrevious: Int { prevStack.count > 0 ? prevStack.count - 1 : 0 }
	@objc var countForward: Int { nextStack.count }
	@objc var peakCurrent: Entry? { prevStack.last }
	@objc var peakPrevious: Entry? { prevStack.count >= 2 ? prevStack[prevStack.count - 2] : nil }
	@objc var peakForward: Entry? { nextStack.last }
	private var prevStack: [Entry] = []
	private var nextStack: [Entry] = []

	@objc func push(_ entry: Entry) {
		doPush(entry)
		logStack()
	}

	@objc func replaceTopWithEntry(_ entry: Entry) {
		if prevStack.isNotEmpty { prevStack.removeLast() }
		prevStack.append(entry)
		logStack()
	}

	@objc func navigate(to entry: Entry) {
		// move element between stacks until `entry` is "top" (last item) of `prevStack` stack
		if prevStack.contains(entry) {
			while let element = prevStack.last, entry != element {
				prevStack.removeLast()
				nextStack.append(element)
			}
		}
		else if nextStack.contains(entry) {
			while let element = nextStack.last {
				nextStack.removeLast()
				prevStack.append(element)
				if element == entry { break; }
			}
		}
		else {
			// entry not in any stack, push on top, clearing forward history
			doPush(entry)
		}

		logStack()
	}

	// last element is the current item so we won't generate menu item for it.
	@objc func backEntries() -> [Entry] { Array(prevStack.dropLast()) }
	@objc func forwardEntries() -> [Entry] { Array(nextStack) }

	private func doPush(_ entry: Entry) {
		prevStack.append(entry)
		if prevStack.count > 50 {
			prevStack.removeFirst()
		}

		if let last = nextStack.last, last === entry {
			nextStack.removeLast()
		}
		else {
			nextStack.removeAll()
		}
	}

#if DEBUG
	static let LOGGER: OSLog = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "SPTableHistoryManager")
	private func logStack() {
		if (self.prevStack.isNotEmpty) {
			Self.LOGGER.debug("\nPrev Stack: \(makeStackString(self.prevStack, true))")
		}
		if (self.nextStack.isNotEmpty) {
			Self.LOGGER.debug("\nNext Stack: \(makeStackString(self.nextStack, false))")
		}
	}
	private func makeStackString(_ stack: [Entry], _ isPrev: Bool ) -> String {
		guard !stack.isEmpty else { return "[]" }

		var currDb = ""
		var strings = stack.map { entry in
			if currDb == entry.database {
				return "\n  ::\(entry.table ?? "(null)")::\(entry.activeFilter)"
			}
			else {
				currDb = entry.database ?? ""
				return "\n  \(entry.debugDescription)"
			}
		}

		if isPrev {
			strings[strings.count-1] = "\n  <CURRENT> \(strings[strings.count-1].trimmedString)"
		}

		var msg = "["
		msg.append(strings.reversed().joined(separator: ","))
		msg.append("\n]")

		return msg
	}
#else
	private func logStack() {}
#endif
}

@objc class SPTableHistoryEntry: NSObject {
	@objc var database: String?
	@objc var table: String?
	@objc var view: Int
	@objc var viewPort: NSRect
	@objc var contentSortColName: String?
	@objc var contentSortColIsAsc: Bool
	@objc var contentPageNumber: Int
	@objc var activeFilter: Int
	@objc var selectedRows: [String: Any]?
	@objc var filter: [String: Any]?
	@objc var filterData: Data?
	@objc weak var cachedMenuItem: NSMenuItem?
	override var description: String { "\(database ?? "<null>").\(table ?? "<null>")" }

	@objc init(database: String?, table: String?, view: Int, viewPort: NSRect,
			   contentSortColName: String?, contentSortColIsAsc: Bool, contentPageNumber: Int, selectedRows: [String: Any]?,
			   activeFilter: Int, filter: [String: Any]?, filterData: Data?) {
		self.database = database
		self.table = table
		self.view = view
		self.viewPort = viewPort
		self.contentSortColName = contentSortColName
		self.contentSortColIsAsc = contentSortColIsAsc
		self.contentPageNumber = contentPageNumber
		self.activeFilter = activeFilter
		self.selectedRows = selectedRows
		self.filter = filter
		self.filterData = filterData
		super.init()
	}
}
