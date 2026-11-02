//
//  SAFavoriteNewFolderPlacementTests.swift
//  Unit Tests
//
//  Pins where -[SPConnectionController addGroup:] puts a new folder: always top-level on the Claude connection page
//  (cards, no tree), beside the selection in the classic sidebar (upstream).
//

import XCTest

final class SAFavoriteNewFolderPlacementTests: XCTestCase {

    private func parent(folder: Bool = false, quickConnect: Bool = false, selected: Bool = true, cards: Bool) -> SAFavoriteNewFolderParent {
        SAFavoriteNewFolderPlacement.parent(selectionIsFolder: folder, selectionIsQuickConnect: quickConnect,
                                            hasSelection: selected, favouritesShowAsCards: cards)
    }

    // MARK: - Connection page (cards)

    func testCardsWithFavouriteInsideAFolderSelectedAddsATopLevelFolder() {
        XCTAssertEqual(parent(folder: false, cards: true), .topLevel)
    }

    func testCardsWithAFolderSelectedAddsATopLevelFolder() {
        XCTAssertEqual(parent(folder: true, cards: true), .topLevel)
    }

    func testCardsWithQuickConnectOrNothingSelectedAddsATopLevelFolder() {
        XCTAssertEqual(parent(quickConnect: true, cards: true), .topLevel)
        XCTAssertEqual(parent(selected: false, cards: true), .topLevel)
    }

    // MARK: - Classic sidebar (outline tree): upstream behaviour

    func testOutlineWithAFolderSelectedNestsInsideIt() {
        XCTAssertEqual(parent(folder: true, cards: false), .selectedNode)
    }

    func testOutlineWithAFavouriteSelectedAddsBesideIt() {
        XCTAssertEqual(parent(folder: false, cards: false), .selectedNodeParent)
    }

    func testOutlineWithQuickConnectOrNothingSelectedAddsATopLevelFolder() {
        XCTAssertEqual(parent(folder: true, quickConnect: true, cards: false), .topLevel)
        XCTAssertEqual(parent(selected: false, cards: false), .topLevel)
    }
}
