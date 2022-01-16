//
// Created by Luis Aguiniga on January 9, 2022
// Copyright (c) 2022 Sequel-Ace. All rights reserved.
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
//
//  More info at <https://github.com/sequelpro/sequelpro>

import AppKit
import XCTest

// added private so that this class is not in the generated -Swift.h
private class TableSortHelperTests: XCTestCase {
    typealias Order = TableSortHelper.SortOrder

    // sample data with different attributes to sort by
    private static func seedData() -> NSArray {
        [
            TestData("a", 1, 40.0, false),
            TestData("b", 3, 20.0, false),
            TestData("c", 2, 10.0, true),
            TestData("d", 4, 30.0, true),
        ]
    }

    func testCycleThroughAscendingDescendingDefaultOnIntColumn() {
        let data = Self.seedData()
        var sdata: [Any] = []
        let table = Self.buildTestTable()
        let helper = Self.buildTestHelper(with: table)

        // click once for ascending
        sdata = clickThenSort(table, 1, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.ascending)
        verifyThroughIntsOrder([1, 2, 3, 4], sdata)

        // click a second time for descending
        sdata = clickThenSort(table, 1, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.descending)
        verifyThroughIntsOrder([4, 3, 2, 1], sdata)

        // click a second time for "default" order
        sdata = clickThenSort(table, 1, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.default)
        verifyThroughIntsOrder([1, 3, 2, 4], sdata)
    }

    func testCycleThroughAscendingDescendingDefaultOnDoubleColumn() {
        let data = Self.seedData()
        var sdata: [Any] = []
        let table = Self.buildTestTable()
        let helper = Self.buildTestHelper(with: table)

        // click once for ascending
        sdata = clickThenSort(table, 2, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.ascending)
        verifyThroughDoublesOrder([10.0, 20.0, 30.0, 40.0], sdata)

        // click a second time for descending
        sdata = clickThenSort(table, 2, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.descending)
        verifyThroughDoublesOrder([40.0, 30.0, 20.0, 10.0], sdata)

        // click a second time for "default" order
        sdata = clickThenSort(table, 2, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.default)
        verifyThroughDoublesOrder([40.0, 20.0, 10.0, 30.0], sdata)
    }

    func testSortingDifferentColumnsOnEveryClick() {
        let data = Self.seedData()
        var sdata: [Any] = []
        let table = Self.buildTestTable()
        let helper = Self.buildTestHelper(with: table)

        // sort by strings -- ascending
        sdata = clickThenSort(table, 0, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.ascending)
        verifyThroughIntsOrder([1,3,2,4], sdata)

        // sort by ints -- ascending ascending
        sdata = clickThenSort(table, 1, helper, data)
        verifyThroughIntsOrder([1,2,3,4], sdata)

        // sort by doubles -- ascending
        sdata = clickThenSort(table, 2, helper, data)
        XCTAssertEqual(helper.currentOrder, Order.ascending)
        verifyThroughIntsOrder([2,3,4,1], sdata)
    }

    func testIndicatorImageManagement() {
        let table = Self.buildTestTable()
        let helper = Self.buildTestHelper(with: table)

        // click once for ascending
        XCTAssertNil(table.indicatorImage(in: table.tableColumns[1]))
        _ = helper.sortDescriptorForClick(on: table, column: table.tableColumns[1])
        XCTAssertEqual(table.indicatorImage(in: table.tableColumns[1]), Order.ascending.indicatorImage!)

        // click a second time for descending
        _ = helper.sortDescriptorForClick(on: table, column: table.tableColumns[1])
        XCTAssertEqual(table.indicatorImage(in: table.tableColumns[1]), Order.descending.indicatorImage!)

        // click on a differnt column
        XCTAssertNil(table.indicatorImage(in: table.tableColumns[2]))
        _ = helper.sortDescriptorForClick(on: table, column: table.tableColumns[2])
        XCTAssertEqual(table.indicatorImage(in: table.tableColumns[2]), Order.ascending.indicatorImage!)
        
        // check first column has indidator cleared
        XCTAssertNil(table.indicatorImage(in: table.tableColumns[1]))
    }

    func testAttemptingToSortColumnForWhichWeDontHaveADescriptor() {

    }

    private func clickThenSort(_ tv: NSTableView, _ tcIdx: Int, _ helper: TableSortHelper,  _ input: NSArray) -> [Any] {
        let descriptor = helper.sortDescriptorForClick(on: tv, column: tv.tableColumns[tcIdx])
        XCTAssertNotNil(descriptor)
        return input.sortedArray(using: [descriptor!])
    }

    private func verifyThroughStringsOrder(_ expected: [String], _ actual: [Any]) {
        XCTAssertEqual(expected.count, actual.count)
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(e, (actual[i] as? TestData)?.col1)
        }
    }

    private func verifyThroughIntsOrder(_ expected: [Int], _ actual: [Any]) {
        XCTAssertEqual(expected.count, actual.count)
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(e, (actual[i] as? TestData)?.col2)
        }
    }

    private func verifyThroughDoublesOrder(_ expected: [Double], _ actual: [Any]) {
        XCTAssertEqual(expected.count, actual.count)
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(e, (actual[i] as? TestData)?.col3)
        }
    }
    
    //private func verifyIndicator(_ tv: NSTableView, columnIndex idx: Int, expected: )

    // Note: Sorting with NSSortDescriptors uses key-value coding so fields
    // here must match the NSSortDescriptors key and the NSTableColumn identifier.
    @objc class TestData: NSObject {
        @objc let col1: String
        @objc let col2: Int
        @objc let col3: Double
        @objc let col4: Bool

        init(_ col1: String, _ col2: Int, _ col3: Double, _ col4: Bool) {
            self.col1 = col1
            self.col2 = col2
            self.col3 = col3
            self.col4 = col4
        }
    }

    private static func buildTestTable() -> NSTableView {
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col1")))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col2")))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col3")))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col4")))
        return table
    }

    private static func buildTestHelper(with table: NSTableView) -> TableSortHelper {
        TableSortHelper(tableView: table, descriptors: [
            // default order at index 0:
            NSSortDescriptor(key: "col1", ascending: true) { (a, b) -> ComparisonResult in
                guard let a = a as? String, let b = b as? String else { fatalError() }
                return a.compare(b)
            },
            NSSortDescriptor(key: "col2", ascending: true) { (a, b) -> ComparisonResult in
                guard let a = a as? Int, let b = b as? Int else { fatalError() }
                return a == b ? .orderedSame : (a < b) ? .orderedAscending : .orderedDescending
            },
            NSSortDescriptor(key: "col3", ascending: true) { (a, b) -> ComparisonResult in
                guard let a = a as? Double, let b = b as? Double else { fatalError() }
                return a == b ? .orderedSame : (a < b) ? .orderedAscending : .orderedDescending
            },
            // Do Descriptor for col4 is intentional.
        ], aliases: [String : String]())
    }

}
