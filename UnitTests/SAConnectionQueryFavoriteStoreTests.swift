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
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: true, isRestoredFromSessionBundle: false, connectionID: "1234"), .connection(id: "1234"))
    }

    func testQuickConnectAndSpfWindowsKeepTheFileList() {
        // Quick connect: no saved connection.
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: true, isRestoredFromSessionBundle: false, connectionID: nil), .document)
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: true, isRestoredFromSessionBundle: false, connectionID: ""), .document)
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: true, isRestoredFromSessionBundle: false, connectionID: "  "), .document)
        // A window opened from (or saved to) an .spf file keeps the file's favourites, even with a connection id.
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: false, isRestoredFromSessionBundle: false, connectionID: "1234"), .document)
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: false, isRestoredFromSessionBundle: false, connectionID: nil), .document)
    }

    func testSessionBundleWindowsKeepTheirBundleList() {
        // A window restored from an .spfs counts as untitled, but its favourites live in the bundle.
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: true, isRestoredFromSessionBundle: true, connectionID: "1234"), .document)
    }

    func testSaveSessionDoesNotMoveAnOpenConnectionWindowOffItsConnection() {
        // "Save Session" writes open untitled windows into the bundle (they stay untitled) but doesn't restore them:
        // they keep their connection's list.
        XCTAssertEqual(SAConnectionLocalScopeKind.resolve(isUntitled: true, isRestoredFromSessionBundle: false, connectionID: "1234"), .connection(id: "1234"))
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

    // MARK: - Manager Save merge

    /// The manager's copies of `base`, as the manager opens them.
    private func copies(_ base: [Any]) -> [AnyObject] {
        base.map { NSMutableDictionary(dictionary: $0 as! NSDictionary) }
    }

    func testUnchangedSectionWritesNothingAndKeepsAnotherWindowsSave() {
        let base: [Any] = [favorite("L1"), favorite("L2")]
        let opened = copies(base)
        let theirs: [Any] = base + [favorite("From B")]
        XCTAssertNil(SAConnectionListMerge.merge(base: base, opened: opened, mine: opened, theirs: theirs))
        // Edited in place back to the same value is unchanged too.
        (opened[0] as! NSMutableDictionary)["query"] = "SELECT 1"
        XCTAssertNil(SAConnectionListMerge.merge(base: base, opened: opened, mine: opened, theirs: theirs))
    }

    func testMyAddKeepsAnotherWindowsAdd() throws {
        let base: [Any] = [favorite("L1")]
        let opened = copies(base)
        let mine: [Any] = opened + [favorite("Mine")]
        let theirs: [Any] = base + [favorite("From B")]
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: mine, theirs: theirs))
        XCTAssertEqual(names(merged), ["L1", "Mine", "From B"])
    }

    func testMyEditDeleteAndReorderApplyAndAnotherWindowsAddSurvives() throws {
        let base: [Any] = [favorite("A"), favorite("B"), favorite("C")]
        let opened = copies(base)
        (opened[0] as! NSMutableDictionary)["query"] = "SELECT 'edited'"
        let mine: [Any] = [opened[2], opened[0]]   // B deleted, C moved up, A edited
        let theirs: [Any] = base + [favorite("From B")]
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: mine, theirs: theirs))
        XCTAssertEqual(names(merged), ["C", "A", "From B"])
        XCTAssertEqual((merged[1] as? NSDictionary)?["query"] as? String, "SELECT 'edited'")
    }

    func testADraggedRowRecreatedAsANewDictionaryStillCountsAsTheSameItem() throws {
        let base: [Any] = [favorite("A"), favorite("B")]
        let opened = copies(base)
        // The manager's drag re-creates the row: same value, new object.
        let mine: [Any] = [NSMutableDictionary(dictionary: opened[1] as! NSDictionary), opened[0]]
        let theirs: [Any] = [favorite("A")]   // another window deleted B meanwhile
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: mine, theirs: theirs))
        XCTAssertEqual(names(merged), ["A"])
    }

    func testAnItemUntouchedHereFollowsAnotherWindowsReplaceInPlace() throws {
        let base: [Any] = [favorite("A"), favorite("B")]
        let opened = copies(base)
        let mine: [Any] = opened + [favorite("Mine")]
        let theirs: [Any] = [favorite("A", query: "SELECT 'replaced in B'"), favorite("B")]
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: mine, theirs: theirs))
        XCTAssertEqual(names(merged), ["A", "B", "Mine"])
        XCTAssertEqual((merged[0] as? NSDictionary)?["query"] as? String, "SELECT 'replaced in B'")
    }

    func testMyEditWinsOverAnotherWindowsEditOfTheSameItem() throws {
        let base: [Any] = [favorite("A")]
        let opened = copies(base)
        (opened[0] as! NSMutableDictionary)["query"] = "SELECT 'mine'"
        let theirs: [Any] = [favorite("A", query: "SELECT 'theirs'")]
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: opened, theirs: theirs))
        // Mine kept; theirs is a different value, kept too (never dropped silently).
        XCTAssertEqual(merged.compactMap { ($0 as? NSDictionary)?["query"] as? String }, ["SELECT 'mine'", "SELECT 'theirs'"])
    }

    func testAnItemAnotherWindowDeletedThatIDidNotTouchStaysDeleted() throws {
        let base: [Any] = [favorite("A"), favorite("B")]
        let opened = copies(base)
        let mine: [Any] = opened + [favorite("Mine")]
        let theirs: [Any] = [favorite("B")]
        let merged = try XCTUnwrap(SAConnectionListMerge.merge(base: base, opened: opened, mine: mine, theirs: theirs))
        XCTAssertEqual(names(merged), ["B", "Mine"])
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
