//
//  SPSplitViewTests.swift
//  Unit Tests
//
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SPSplitViewTests: XCTestCase {

    /// An SPSplitView created in code without subviews initialises and lays out.
    func testSplitViewWithoutSubviewsInitialisesAndLaysOut() throws {
        let splitViewClass = try XCTUnwrap(NSClassFromString("SPSplitView") as? NSSplitView.Type)

        let splitView = splitViewClass.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        splitView.adjustSubviews()
        splitView.setFrameSize(NSSize(width: 500, height: 320))
        splitView.layoutSubtreeIfNeeded()

        XCTAssertTrue(splitView.subviews.isEmpty)
    }

    func testSplitViewWithSubviewsStillLaysThemOut() throws {
        let splitViewClass = try XCTUnwrap(NSClassFromString("SPSplitView") as? NSSplitView.Type)

        let splitView = splitViewClass.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        splitView.isVertical = true
        splitView.addSubview(NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 300)))
        splitView.addSubview(NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 300)))
        splitView.adjustSubviews()

        let widths = splitView.subviews.map(\.frame.width)
        XCTAssertEqual(widths.count, 2)
        XCTAssertEqual(widths.reduce(0, +) + splitView.dividerThickness, 400, accuracy: 0.5)
    }
}
