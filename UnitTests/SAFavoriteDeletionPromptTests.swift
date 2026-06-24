//
//  SAFavoriteDeletionPromptTests.swift
//  Unit Tests
//
//  Pins the delete-confirmation rules lifted out of
//  -[SPConnectionController removeNode:] (Phase D2).
//

import XCTest

final class SAFavoriteDeletionPromptTests: XCTestCase {

    func testFavoriteAlwaysNeedsConfirmationWithFavoriteWording() {
        let prompt = SAFavoriteDeletionPrompt.prompt(forGroup: false, name: "Prod", childCount: 0)

        XCTAssertTrue(prompt.needsConfirmation)
        XCTAssertEqual(prompt.title, "Delete favorite 'Prod'?")
        XCTAssertEqual(prompt.informativeText,
                       "Are you sure you want to delete the favorite 'Prod'? This operation cannot be undone.")
    }

    func testGroupWithChildrenNeedsConfirmationWithGroupWording() {
        let prompt = SAFavoriteDeletionPrompt.prompt(forGroup: true, name: "Work", childCount: 3)

        XCTAssertTrue(prompt.needsConfirmation)
        XCTAssertEqual(prompt.title, "Delete group 'Work'?")
        XCTAssertEqual(prompt.informativeText,
                       "Are you sure you want to delete the group 'Work'? All groups and favorites within this group will also be deleted. This operation cannot be undone.")
    }

    func testEmptyGroupSkipsConfirmation() {
        let prompt = SAFavoriteDeletionPrompt.prompt(forGroup: true, name: "Empty", childCount: 0)

        XCTAssertFalse(prompt.needsConfirmation)
        XCTAssertEqual(prompt.title, "")
        XCTAssertEqual(prompt.informativeText, "")
    }

    func testFavoriteWithChildCountStillUsesFavoriteWording() {
        // childCount is only meaningful for groups; favorites ignore it.
        let prompt = SAFavoriteDeletionPrompt.prompt(forGroup: false, name: "Solo", childCount: 9)

        XCTAssertTrue(prompt.needsConfirmation)
        XCTAssertEqual(prompt.title, "Delete favorite 'Solo'?")
    }

    func testNilNameFormatsAsEmptyString() {
        let prompt = SAFavoriteDeletionPrompt.prompt(forGroup: false, name: nil, childCount: 0)

        XCTAssertTrue(prompt.needsConfirmation)
        XCTAssertEqual(prompt.title, "Delete favorite ''?")
    }
}
