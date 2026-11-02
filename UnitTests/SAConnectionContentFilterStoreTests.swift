//
//  SAConnectionContentFilterStoreTests.swift
//  Unit Tests
//
//  Pins content filters per saved connection (walkthrough item 18, SAConnectionQueryFavoriteStore.swift): a write
//  touches only its connection and field type, the Content Filter manager's Save merges with other windows' saves
//  although it saves converted copies of its rows, and the managers' section walk.
//

import XCTest

final class SAConnectionContentFilterStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SAConnectionContentFilterStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// A filter as the manager stores it.
    private func filter(_ label: String, clause: String = "= ${}", arguments: Int = 1) -> NSDictionary {
        ["MenuLabel": label, "Clause": clause, "NumberOfArguments": arguments] as NSDictionary
    }

    private func labels(_ filters: [Any]) -> [String] {
        filters.compactMap { ($0 as? NSDictionary)?["MenuLabel"] as? String }
    }

    /// The manager's rows for `base` (mutable copies, as SAContentFilterLocalScope hands them out).
    private func rows(_ base: [Any]) -> [AnyObject] {
        base.map { NSMutableDictionary(dictionary: $0 as! NSDictionary) }
    }

    /// The manager's Save of `rows`: new dictionaries equal to the rows (its -contentFilterForFileURL: converts every
    /// row into a new dictionary in the stored shape).
    private func saved(_ rows: [AnyObject]) -> [Any] {
        rows.map { NSDictionary(dictionary: $0 as! NSDictionary) }
    }

    // MARK: - Store

    func testEmptyStoreHasNoFilters() {
        let store = SAConnectionContentFilterStore(defaults: defaults)
        XCTAssertTrue(store.filters(forConnectionID: "1", filterType: "number").isEmpty)
    }

    func testAWriteTouchesOnlyItsConnectionAndFieldType() {
        let store = SAConnectionContentFilterStore(defaults: defaults)
        store.setFilters([filter("N1")], forConnectionID: "1", filterType: "number")
        store.setFilters([filter("S1"), filter("S2")], forConnectionID: "1", filterType: "string")
        store.setFilters([filter("Other")], forConnectionID: "2", filterType: "number")

        store.setFilters([filter("N1 edited")], forConnectionID: "1", filterType: "number")

        XCTAssertEqual(labels(store.filters(forConnectionID: "1", filterType: "number")), ["N1 edited"])
        XCTAssertEqual(labels(store.filters(forConnectionID: "1", filterType: "string")), ["S1", "S2"])
        XCTAssertEqual(labels(store.filters(forConnectionID: "2", filterType: "number")), ["Other"])
        XCTAssertTrue(store.filters(forConnectionID: "1", filterType: "date").isEmpty)
    }

    func testFiltersKeepEveryKeyAndSurviveANewStore() {
        let stored: NSDictionary = ["MenuLabel": "Between", "Clause": "BETWEEN ${} AND ${}", "NumberOfArguments": 2,
                                    "ConjunctionLabels": ["AND"], "SuppressLeadingFieldPlaceholder": false]
        SAConnectionContentFilterStore(defaults: defaults).setFilters([stored], forConnectionID: "7", filterType: "number")
        let read = SAConnectionContentFilterStore(defaults: defaults).filters(forConnectionID: "7", filterType: "number")
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first as? NSDictionary, stored)
    }

    func testEmptyingATypeRemovesItAndTheLastTypeRemovesTheConnection() {
        let store = SAConnectionContentFilterStore(defaults: defaults)
        store.setFilters([filter("N")], forConnectionID: "1", filterType: "number")
        store.setFilters([filter("S")], forConnectionID: "1", filterType: "string")

        store.setFilters([], forConnectionID: "1", filterType: "number")
        let entry = defaults.dictionary(forKey: SAConnectionContentFilterStore.defaultsKey)?["1"] as? [String: Any]
        XCTAssertEqual(entry.map { Array($0.keys) }, ["string"])

        store.setFilters([], forConnectionID: "1", filterType: "string")
        XCTAssertNil(defaults.dictionary(forKey: SAConnectionContentFilterStore.defaultsKey)?["1"])
    }

    func testTheStoreNeverTouchesTheGlobalFiltersOrTheQueryFavorites() {
        // keep in sync with SPConstants.m (SPContentFilters)
        let global = ["number": [filter("Global")]]
        defaults.set(global, forKey: "ContentFilters")
        SAConnectionQueryFavoriteStore(defaults: defaults).setFavorites([["name": "Q", "query": "SELECT 1"]], forConnectionID: "1")

        SAConnectionContentFilterStore(defaults: defaults).setFilters([filter("Local")], forConnectionID: "1", filterType: "number")

        XCTAssertEqual(defaults.dictionary(forKey: "ContentFilters") as NSDictionary?, global as NSDictionary)
        XCTAssertEqual(SAConnectionQueryFavoriteStore(defaults: defaults).favorites(forConnectionID: "1").count, 1)
        XCTAssertNotEqual(SAConnectionContentFilterStore.defaultsKey, SAConnectionQueryFavoriteStore.defaultsKey)
    }

    func testMalformedEntriesReadAsEmptyAndOtherConnectionsAreKept() {
        defaults.set(["1": "not a dictionary", "2": ["number": "not a list"], "3": ["number": [filter("Kept")]]],
                     forKey: SAConnectionContentFilterStore.defaultsKey)
        let store = SAConnectionContentFilterStore(defaults: defaults)
        XCTAssertTrue(store.filters(forConnectionID: "1", filterType: "number").isEmpty)
        XCTAssertTrue(store.filters(forConnectionID: "2", filterType: "number").isEmpty)

        store.setFilters([filter("New")], forConnectionID: "1", filterType: "number")

        XCTAssertEqual(labels(store.filters(forConnectionID: "1", filterType: "number")), ["New"])
        XCTAssertEqual(labels(store.filters(forConnectionID: "3", filterType: "number")), ["Kept"])
        XCTAssertEqual((defaults.dictionary(forKey: SAConnectionContentFilterStore.defaultsKey)?["2"] as? [String: Any])?["number"] as? String,
                       "not a list")
    }

    // MARK: - The manager's Save (converted copies of its rows)

    func testUnchangedSectionWritesNothingAlthoughSavedAsNewDictionaries() {
        let base: [Any] = [filter("A"), filter("B")]
        let opened = rows(base)
        let theirs: [Any] = base + [filter("FromB")]
        XCTAssertNil(SAConnectionListMerge.merge(base: base, opened: opened, mine: saved(opened), mineIdentities: opened,
                                                 theirs: theirs, nameKey: "MenuLabel"))
    }

    func testMyEditAndAddKeepAnotherWindowsAdd() throws {
        let base: [Any] = [filter("A"), filter("B")]
        let opened = rows(base)
        (opened[1] as! NSMutableDictionary)["Clause"] = "> ${}"
        let mine = opened + [NSMutableDictionary(dictionary: filter("Mine"))]
        let theirs: [Any] = base + [filter("FromB")]

        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: saved(mine),
                                                               mineIdentities: mine, theirs: theirs, nameKey: "MenuLabel"))
        XCTAssertEqual(labels(merged), ["A", "B", "Mine", "FromB"])
        XCTAssertEqual((merged[1] as? NSDictionary)?["Clause"] as? String, "> ${}")
    }

    func testAnUntouchedFilterFollowsAnotherWindowsEditMatchedByMenuLabel() throws {
        let base: [Any] = [filter("A"), filter("B")]
        let opened = rows(base)
        let mine = [opened[0], opened[1], NSMutableDictionary(dictionary: filter("Mine"))]
        let theirs: [Any] = [filter("A"), filter("B", clause: "LIKE ${}")]

        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: saved(mine),
                                                               mineIdentities: mine, theirs: theirs, nameKey: "MenuLabel"))
        XCTAssertEqual(labels(merged), ["A", "B", "Mine"])
        XCTAssertEqual((merged[1] as? NSDictionary)?["Clause"] as? String, "LIKE ${}")
    }

    func testMismatchedIdentitiesFallBackToMatchingByEquality() throws {
        let base: [Any] = [filter("A")]
        let opened = rows(base)
        let mine = opened + [NSMutableDictionary(dictionary: filter("Mine"))]
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: saved(mine),
                                                               mineIdentities: [opened[0]], theirs: base + [filter("FromB")],
                                                               nameKey: "MenuLabel"))
        XCTAssertEqual(labels(merged), ["A", "Mine", "FromB"])
    }

    // MARK: - The managers' section walk

    func testSectionItemsRunFromTheirHeaderToTheNextHeader() {
        let global: NSDictionary = ["MenuLabel": "Global", "headerOfFileURL": ""]
        let file: NSDictionary = ["MenuLabel": "Untitled 1", "headerOfFileURL": "file:///Untitled%201"]
        let g1 = filter("G1"), l1 = filter("L1"), l2 = filter("L2")
        let items: NSArray = [global, g1, file, l1, l2]

        XCTAssertEqual(SAManagerDocumentSection.items(in: items, sectionHeader: "file:///Untitled%201").map { $0 as AnyObject }
            .map(ObjectIdentifier.init), [l1, l2].map(ObjectIdentifier.init))
        XCTAssertEqual(labels(SAManagerDocumentSection.items(in: items, sectionHeader: "")), ["G1"])
        XCTAssertTrue(SAManagerDocumentSection.items(in: items, sectionHeader: "file:///Other").isEmpty)
        XCTAssertTrue(SAManagerDocumentSection.items(in: [global, g1, file] as NSArray, sectionHeader: "file:///Untitled%201").isEmpty)
    }
}
