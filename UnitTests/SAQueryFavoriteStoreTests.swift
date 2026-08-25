//
//  SAQueryFavoriteStoreTests.swift
//  Unit Tests
//
//  Pins query-favorite replacement identity and metadata preservation.
//


import XCTest

final class SAQueryFavoriteStoreTests: XCTestCase {

    func testSelectionsKeepScopeAndRealSourceIndex() {
        let malformed = "not a dictionary"
        let document: [Any] = [malformed, favorite("Document")]
        let global: [Any] = [favorite("Global")]

        let selections = SAQueryFavoriteStore.selections(
            documentFavorites: document,
            globalFavorites: global
        )

        XCTAssertEqual(selections.count, 2)
        XCTAssertEqual(selections[0].scope, .document)
        XCTAssertEqual(selections[0].originalIndex, 1)
        XCTAssertEqual(selections[0].name, "Document")
        XCTAssertEqual(selections[1].scope, .global)
        XCTAssertEqual(selections[1].originalIndex, 0)
        XCTAssertEqual(selections[1].name, "Global")
    }

    func testCreatingDocumentFavoriteAppendsWithoutDroppingMalformedEntries() throws {
        let document: [Any] = ["legacy-entry"]

        let mutation = try SAQueryFavoriteStore.save(
            query: "SELECT 1",
            name: "One",
            saveGlobally: false,
            replacing: nil,
            documentFavorites: document,
            globalFavorites: []
        )

        XCTAssertEqual(mutation.scope, .document)
        XCTAssertEqual(mutation.favorites.count, 2)
        XCTAssertEqual(mutation.favorites[0] as? String, "legacy-entry")
        XCTAssertEqual((mutation.favorites[1] as? NSDictionary)?["name"] as? String, "One")
        XCTAssertEqual((mutation.favorites[1] as? NSDictionary)?["query"] as? String, "SELECT 1")
    }

    func testCreatingGlobalFavoriteUsesGlobalList() throws {
        let mutation = try SAQueryFavoriteStore.save(
            query: "SELECT 2",
            name: "Two",
            saveGlobally: true,
            replacing: nil,
            documentFavorites: [favorite("Document")],
            globalFavorites: [favorite("Existing")]
        )

        XCTAssertEqual(mutation.scope, .global)
        XCTAssertEqual(mutation.favorites.count, 2)
        XCTAssertEqual((mutation.favorites[1] as? NSDictionary)?["name"] as? String, "Two")
    }

    func testCreatingFavoriteRequiresAName() {
        XCTAssertThrowsError(try SAQueryFavoriteStore.save(
            query: "SELECT 1",
            name: "",
            saveGlobally: false,
            replacing: nil,
            documentFavorites: [],
            globalFavorites: []
        )) { error in
            XCTAssertEqual(error as? SAQueryFavoriteSaveError, .nameRequired)
        }
    }

    func testReplacementUpdatesOnlyQueryAndIgnoresNewFavoriteInputs() throws {
        let original = favorite("Production", query: "SELECT old", tabTrigger: "prod")
        let selections = SAQueryFavoriteStore.selections(
            documentFavorites: [original],
            globalFavorites: []
        )

        let mutation = try SAQueryFavoriteStore.save(
            query: "SELECT new",
            name: "Ignored Name",
            saveGlobally: true,
            replacing: selections[0],
            documentFavorites: [original],
            globalFavorites: []
        )

        XCTAssertEqual(mutation.scope, .document)
        let replaced = try XCTUnwrap(mutation.favorites[0] as? NSDictionary)
        XCTAssertEqual(replaced["name"] as? String, "Production")
        XCTAssertEqual(replaced["query"] as? String, "SELECT new")
        XCTAssertEqual(replaced["tabtrigger"] as? String, "prod")
    }

    func testReplacementUsesSelectedGlobalList() throws {
        let document = favorite("Document")
        let global = favorite("Global", query: "SELECT old")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [document],
            globalFavorites: [global]
        )[1]

        let mutation = try SAQueryFavoriteStore.save(
            query: "SELECT new",
            name: "",
            saveGlobally: false,
            replacing: selection,
            documentFavorites: [document],
            globalFavorites: [global]
        )

        XCTAssertEqual(mutation.scope, .global)
        XCTAssertEqual(mutation.favorites.count, 1)
        XCTAssertEqual((mutation.favorites[0] as? NSDictionary)?["name"] as? String, "Global")
        XCTAssertEqual((mutation.favorites[0] as? NSDictionary)?["query"] as? String, "SELECT new")
    }

    func testReplacementReResolvesUniqueFavoriteAfterInsertion() throws {
        let selected = favorite("Selected", query: "SELECT old")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [selected],
            globalFavorites: []
        )[0]
        let inserted = favorite("Inserted")

        let mutation = try SAQueryFavoriteStore.save(
            query: "SELECT new",
            name: "",
            saveGlobally: false,
            replacing: selection,
            documentFavorites: [inserted, selected],
            globalFavorites: []
        )

        XCTAssertEqual((mutation.favorites[0] as? NSDictionary)?["name"] as? String, "Inserted")
        XCTAssertEqual((mutation.favorites[1] as? NSDictionary)?["query"] as? String, "SELECT new")
    }

    func testReplacementFailsWhenFavoriteWasRemoved() {
        let selected = favorite("Selected")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [selected],
            globalFavorites: []
        )[0]

        assertSelectedFavoriteChanged(selection: selection, current: [])
    }

    func testReplacementFailsWhenFavoriteWasEdited() {
        let selected = favorite("Selected", query: "SELECT old")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [selected],
            globalFavorites: []
        )[0]
        let edited = favorite("Selected", query: "SELECT edited elsewhere")

        assertSelectedFavoriteChanged(selection: selection, current: [edited])
    }

    func testReplacementFailsWhenShiftedIdenticalFavoritesAreAmbiguous() {
        let selected = favorite("Duplicate")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [selected],
            globalFavorites: []
        )[0]
        let inserted = favorite("Inserted")

        assertSelectedFavoriteChanged(
            selection: selection,
            current: [inserted, selected, NSDictionary(dictionary: selected)]
        )
    }

    func testReplacementUsesOriginalIndexWhenIdenticalFavoriteRemainsThere() throws {
        let duplicate = favorite("Duplicate")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [duplicate, duplicate],
            globalFavorites: []
        )[1]

        let mutation = try SAQueryFavoriteStore.save(
            query: "SELECT replacement",
            name: "",
            saveGlobally: false,
            replacing: selection,
            documentFavorites: [duplicate, duplicate],
            globalFavorites: []
        )

        XCTAssertEqual((mutation.favorites[0] as? NSDictionary)?["query"] as? String, "SELECT 1")
        XCTAssertEqual((mutation.favorites[1] as? NSDictionary)?["query"] as? String, "SELECT replacement")
    }

    func testReplacementFailsWhenSelectedDuplicateWasRemovedAndAnotherShiftedIntoItsIndex() {
        let duplicate = favorite("Duplicate")
        let selection = SAQueryFavoriteStore.selections(
            documentFavorites: [duplicate, duplicate],
            globalFavorites: []
        )[0]

        assertSelectedFavoriteChanged(selection: selection, current: [duplicate])
    }

    private func assertSelectedFavoriteChanged(selection: SAQueryFavoriteSelection,
                                               current: [Any],
                                               file: StaticString = #filePath,
                                               line: UInt = #line) {
        XCTAssertThrowsError(try SAQueryFavoriteStore.save(
            query: "SELECT new",
            name: "",
            saveGlobally: false,
            replacing: selection,
            documentFavorites: current,
            globalFavorites: []
        ), file: file, line: line) { error in
            XCTAssertEqual(error as? SAQueryFavoriteSaveError, .selectedFavoriteChanged, file: file, line: line)
        }
    }

    private func favorite(_ name: String,
                          query: String = "SELECT 1",
                          tabTrigger: String? = nil) -> NSDictionary {
        let favorite = NSMutableDictionary(dictionary: ["name": name, "query": query])
        if let tabTrigger {
            favorite["tabtrigger"] = tabTrigger
        }
        return favorite
    }
}
