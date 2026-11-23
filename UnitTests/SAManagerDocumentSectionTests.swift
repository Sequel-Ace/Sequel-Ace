//
//  SAManagerDocumentSectionTests.swift
//  Unit Tests
//
//  The Query Favorites and Content Filter managers hide an empty document ("Untitled N") section in a window that isn't a
//  saved file, keeping the model as it is (SAManagerDocumentSection.swift).
//

import AppKit
import XCTest

final class SAManagerDocumentSectionTests: XCTestCase {

    private let key = SAManagerDocumentSection.headerKey

    private func header(_ name: String, _ url: String) -> NSDictionary { [key: url, "name": name] as NSDictionary }
    private func item(_ name: String) -> NSMutableDictionary { ["name": name, "query": "SELECT 1"] as NSMutableDictionary }

    /// "Global", two favourites, the document header, then `documentItems` favourites — as the managers build it.
    private func items(documentItems: Int = 0) -> NSMutableArray {
        let items = NSMutableArray(array: [header("Global", ""), item("a"), item("b"), header("Untitled 1", "Untitled%201")])
        for i in 0..<documentItems { items.add(item("doc \(i)")) }
        return items
    }

    private func names(_ controller: NSArrayController) -> [String] {
        (controller.arrangedObjects as? [NSDictionary] ?? []).map { $0["name"] as? String ?? "" }
    }

    func testOnlyAnEmptyUntitledSectionIsHidden() {
        let empty = items()
        XCTAssertTrue(SAManagerDocumentSection.emptyUntitledHeader(in: empty, documentIsUntitled: true) === empty.lastObject as AnyObject)
        // A saved .spf file keeps its section, empty or not.
        XCTAssertNil(SAManagerDocumentSection.emptyUntitledHeader(in: empty, documentIsUntitled: false))
        // Never hide favourites.
        XCTAssertNil(SAManagerDocumentSection.emptyUntitledHeader(in: items(documentItems: 1), documentIsUntitled: true))
        // Global is never the one hidden.
        XCTAssertNil(SAManagerDocumentSection.emptyUntitledHeader(in: NSMutableArray(array: [header("Global", "")]), documentIsUntitled: true))
        // A last item that isn't a header is a favourite.
        XCTAssertNil(SAManagerDocumentSection.emptyUntitledHeader(in: NSMutableArray(array: [header("Global", ""), item("a")]), documentIsUntitled: true))
    }

    func testTheListLeavesTheHeaderOutAndRowsStayTheModelsIndexes() {
        let model = items()
        let controller = NSArrayController()
        XCTAssertTrue(SAManagerDocumentSection.hideEmptySection(in: controller, items: model, documentIsUntitled: true))
        controller.content = model
        XCTAssertEqual(names(controller), ["Global", "a", "b"])
        XCTAssertEqual(SAManagerDocumentSection.visibleRowCount(of: model), 3)
        XCTAssertEqual(model.count, 4, "the model keeps the header")
        for (row, object) in (controller.arrangedObjects as! [AnyObject]).enumerated() { XCTAssertTrue(object === model[row] as AnyObject) }
    }

    /// Adding to Global (before the header), removing and reordering keep it hidden.
    func testEditsBeforeTheHeaderKeepItHidden() {
        let model = items()
        let controller = NSArrayController()
        SAManagerDocumentSection.hideEmptySection(in: controller, items: model, documentIsUntitled: true)
        controller.content = model
        model.insert(item("c"), at: 3)
        controller.rearrangeObjects()
        XCTAssertEqual(names(controller), ["Global", "a", "b", "c"])
        model.removeObject(at: 1)
        model.exchangeObject(at: 1, withObjectAt: 2)
        controller.rearrangeObjects()
        XCTAssertEqual(names(controller), ["Global", "c", "b"])
        XCTAssertEqual(SAManagerDocumentSection.visibleRowCount(of: model), 3)
        // The controller's own insertion doesn't drop the filter.
        controller.insert(item("d"), atArrangedObjectIndex: 1)
        XCTAssertNotNil(controller.filterPredicate)
        XCTAssertFalse(names(controller).contains("Untitled 1"))
    }

    /// Should anything ever land after the header, the header shows again: a row never stands for another item.
    func testAnItemAfterTheHeaderShowsItAgain() {
        let model = items()
        let controller = NSArrayController()
        SAManagerDocumentSection.hideEmptySection(in: controller, items: model, documentIsUntitled: true)
        controller.content = model
        model.add(item("doc"))
        controller.rearrangeObjects()
        XCTAssertEqual(names(controller), ["Global", "a", "b", "Untitled 1", "doc"])
        XCTAssertEqual(SAManagerDocumentSection.visibleRowCount(of: model), 5)
    }

    func testASavedFileOrASectionWithItemsIsLeftAlone() {
        for (model, untitled) in [(items(), false), (items(documentItems: 2), true)] {
            let controller = NSArrayController()
            XCTAssertFalse(SAManagerDocumentSection.hideEmptySection(in: controller, items: model, documentIsUntitled: untitled))
            controller.content = model
            XCTAssertNil(controller.filterPredicate)
            XCTAssertEqual((controller.arrangedObjects as! NSArray).count, model.count)
            XCTAssertEqual(SAManagerDocumentSection.visibleRowCount(of: model), model.count)
        }
    }
}
