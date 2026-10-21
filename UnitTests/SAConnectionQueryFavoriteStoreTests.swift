//
//  SAConnectionQueryFavoriteStoreTests.swift
//  Unit Tests
//
//  Pins query favourites per saved connection (SAConnectionQueryFavoriteStore.swift): which windows store against
//  their connection, that a write touches only its connection's entry, that windows read each other's saves, and the
//  tab-trigger lookup matching SPQueryController's.
//

import XCTest

final class SAConnectionQueryFavoriteStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SAConnectionQueryFavoriteStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func favorite(_ name: String, query: String = "SELECT 1", trigger: String? = nil) -> NSDictionary {
        var dict: [String: Any] = ["name": name, "query": query]
        if let trigger { dict["tabtrigger"] = trigger }
        return dict as NSDictionary
    }

    private func names(_ favorites: [Any]) -> [String] {
        favorites.compactMap { ($0 as? NSDictionary)?["name"] as? String }
    }

    // MARK: - Scope

    func testUntitledWindowOnASavedConnectionStoresAgainstTheConnection() {
        XCTAssertEqual(SAQueryFavoriteLocalScopeKind.resolve(isUntitled: true, connectionID: "1234"), .connection(id: "1234"))
    }

    func testQuickConnectAndSpfWindowsKeepTheFileList() {
        // Quick connect: no saved connection.
        XCTAssertEqual(SAQueryFavoriteLocalScopeKind.resolve(isUntitled: true, connectionID: nil), .document)
        XCTAssertEqual(SAQueryFavoriteLocalScopeKind.resolve(isUntitled: true, connectionID: ""), .document)
        XCTAssertEqual(SAQueryFavoriteLocalScopeKind.resolve(isUntitled: true, connectionID: "  "), .document)
        // A window opened from (or saved to) an .spf file keeps the file's favourites, even with a connection id.
        XCTAssertEqual(SAQueryFavoriteLocalScopeKind.resolve(isUntitled: false, connectionID: "1234"), .document)
        XCTAssertEqual(SAQueryFavoriteLocalScopeKind.resolve(isUntitled: false, connectionID: nil), .document)
    }

    // MARK: - Store

    func testEmptyStoreHasNoFavorites() {
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        XCTAssertTrue(store.favorites(forConnectionID: "1").isEmpty)
    }

    func testSavedFavoritesComeBackInOrderWithTheirKeys() {
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        store.setFavorites([favorite("A", trigger: "sa"), favorite("B")], forConnectionID: "1")

        let read = store.favorites(forConnectionID: "1")
        XCTAssertEqual(names(read), ["A", "B"])
        XCTAssertEqual((read[0] as? NSDictionary)?["tabtrigger"] as? String, "sa")
        XCTAssertEqual((read[0] as? NSDictionary)?["query"] as? String, "SELECT 1")
    }

    func testAWriteTouchesOnlyItsConnection() {
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        store.setFavorites([favorite("Local A")], forConnectionID: "1")
        store.setFavorites([favorite("Beato B")], forConnectionID: "2")
        store.setFavorites([favorite("Local A"), favorite("Local C")], forConnectionID: "1")

        XCTAssertEqual(names(store.favorites(forConnectionID: "1")), ["Local A", "Local C"])
        XCTAssertEqual(names(store.favorites(forConnectionID: "2")), ["Beato B"])
    }

    func testTheStoreNeverTouchesTheGlobalFavorites() {
        defaults.set([favorite("Global")], forKey: "queryFavorites")
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        store.setFavorites([favorite("Local")], forConnectionID: "1")
        store.setFavorites([], forConnectionID: "1")

        XCTAssertEqual(names(defaults.array(forKey: "queryFavorites") ?? []), ["Global"])
    }

    func testEmptyingAConnectionRemovesOnlyItsEntry() {
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        store.setFavorites([favorite("A")], forConnectionID: "1")
        store.setFavorites([favorite("B")], forConnectionID: "2")
        store.setFavorites([], forConnectionID: "1")

        let all = defaults.dictionary(forKey: SAConnectionQueryFavoriteStore.defaultsKey)
        XCTAssertNil(all?["1"])
        XCTAssertEqual(names(store.favorites(forConnectionID: "2")), ["B"])
    }

    func testTwoWindowsOnTheSameConnectionSeeEachOthersSaves() {
        // Each window resolves its own store value; both read the shared defaults fresh.
        let windowA = SAConnectionQueryFavoriteStore(defaults: defaults)
        let windowB = SAConnectionQueryFavoriteStore(defaults: defaults)

        windowA.setFavorites(windowA.favorites(forConnectionID: "7") + [favorite("From A")], forConnectionID: "7")
        windowB.setFavorites(windowB.favorites(forConnectionID: "7") + [favorite("From B")], forConnectionID: "7")

        XCTAssertEqual(names(windowA.favorites(forConnectionID: "7")), ["From A", "From B"])
    }

    func testFavoritesSurviveANewStoreOnTheSameDefaults() {
        // As after a restart: the list is in the defaults, not in memory.
        SAConnectionQueryFavoriteStore(defaults: defaults).setFavorites([favorite("Kept")], forConnectionID: "9")
        XCTAssertEqual(names(SAConnectionQueryFavoriteStore(defaults: defaults).favorites(forConnectionID: "9")), ["Kept"])
    }

    func testMalformedStoredValuesReadAsEmptyAndOtherEntriesAreKept() {
        defaults.set(["1": "not a list", "2": [favorite("B")]], forKey: SAConnectionQueryFavoriteStore.defaultsKey)
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        XCTAssertTrue(store.favorites(forConnectionID: "1").isEmpty)

        store.setFavorites([favorite("A")], forConnectionID: "3")
        XCTAssertEqual(names(store.favorites(forConnectionID: "2")), ["B"])
        XCTAssertEqual(names(store.favorites(forConnectionID: "3")), ["A"])
        XCTAssertEqual(defaults.dictionary(forKey: SAConnectionQueryFavoriteStore.defaultsKey)?["1"] as? String, "not a list")
    }

    func testSaveSheetMutationLandsInTheConnectionList() throws {
        // The save sheet's pure mutation, written through the store, as SAQueryFavoriteLocalScope does.
        let store = SAConnectionQueryFavoriteStore(defaults: defaults)
        store.setFavorites([favorite("Existing")], forConnectionID: "1")

        let mutation = try SAQueryFavoriteStore.save(query: "SELECT 2", name: "New", saveGlobally: false, replacing: nil,
                                                     documentFavorites: store.favorites(forConnectionID: "1"),
                                                     globalFavorites: [favorite("Global")])
        XCTAssertEqual(mutation.scope, .document)
        store.setFavorites(mutation.favorites, forConnectionID: "1")

        XCTAssertEqual(names(store.favorites(forConnectionID: "1")), ["Existing", "New"])
    }

    // MARK: - Tab triggers

    func testTabTriggerListsEveryLocalMatchThenTheFirstGlobalOne() {
        let local: [Any] = [favorite("L1", trigger: "t"), favorite("L2", trigger: "x"), favorite("L3", trigger: "t")]
        let global: [Any] = ["malformed", favorite("G1", trigger: "t"), favorite("G2", trigger: "t")]

        let matches = SAQueryFavoriteTabTrigger.matches(trigger: "t", local: local, global: global)
        XCTAssertEqual(names(matches), ["L1", "L3", "G1"])
    }

    func testTabTriggerWithoutGlobalsOrWithAnEmptyTrigger() {
        let local: [Any] = [favorite("L1", trigger: "t")]
        let global: [Any] = [favorite("G1", trigger: "t")]

        XCTAssertEqual(names(SAQueryFavoriteTabTrigger.matches(trigger: "t", local: local, global: global, includeGlobals: false)), ["L1"])
        XCTAssertTrue(SAQueryFavoriteTabTrigger.matches(trigger: "", local: local, global: global).isEmpty)
        XCTAssertTrue(SAQueryFavoriteTabTrigger.matches(trigger: "nope", local: local, global: global).isEmpty)
    }
}
