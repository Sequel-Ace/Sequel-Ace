//
//  SAClaudeFavoriteCardLayoutTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeFavoriteCardLayoutTests: XCTestCase {
    private typealias L = SAClaudeFavoriteCardLayout
    private typealias Card = SAClaudeFavoriteCard
    private typealias Model = SAClaudeFavoriteGridModel

    private func card(_ id: String, quick: Bool = false, folder: String? = nil) -> Card {
        Card(id: id, isQuickConnect: quick, name: id, summary: "", badge: "", colorIndex: nil, folderID: folder)
    }

    /// Quick connect + 2 favourites at the top level, folder "Staging" with 3 cards.
    private var sampleModel: Model {
        Model(topLevel: [card("qc", quick: true), card("a"), card("b")],
              folders: [SAClaudeFavoriteFolder(id: "f1", title: "Staging",
                                               cards: [card("s1", folder: "f1"), card("s2", folder: "f1"), card("s3", folder: "f1")])])
    }

    private func frame(of id: String, in items: [L.Item]) -> NSRect? {
        items.first { $0.kind == .card(id) }?.frame
    }

    // MARK: Columns and height

    func testColumnsForWidth() {
        XCTAssertEqual(L.columns(for: 445), 2)
        XCTAssertEqual(L.columns(for: 700), 3)
        XCTAssertEqual(L.columns(for: 960), 4)
        XCTAssertEqual(L.columns(for: 150), 1)
        XCTAssertEqual(L.columns(for: 0), 1)
        XCTAssertEqual(L.columns(for: 5000), 4)
    }

    func testVisibleHeightCap() {
        XCTAssertEqual(L.visibleHeight(contentHeight: 172), 172)
        XCTAssertEqual(L.visibleHeight(contentHeight: 236), 236)
        XCTAssertEqual(L.visibleHeight(contentHeight: 900), 3 * 64 + 2 * 10 + 24)
        XCTAssertEqual(L.visibleHeight(contentHeight: 0), 0)
    }

    // MARK: Item frames

    func testItemFramesAtWidth760() {
        let (items, contentHeight) = L.items(for: sampleModel, width: 760)
        XCTAssertEqual(items.count, 7)
        XCTAssertEqual(frame(of: "qc", in: items), NSRect(x: 0, y: 0, width: 182.5, height: 64))
        XCTAssertEqual(frame(of: "a", in: items), NSRect(x: 192.5, y: 0, width: 182.5, height: 64))
        XCTAssertEqual(frame(of: "b", in: items), NSRect(x: 385, y: 0, width: 182.5, height: 64))
        XCTAssertEqual(items.first { $0.kind == .folderHeader("f1") }?.frame, NSRect(x: 0, y: 74, width: 760, height: 24))
        XCTAssertEqual(frame(of: "s1", in: items), NSRect(x: 0, y: 108, width: 182.5, height: 64))
        XCTAssertEqual(frame(of: "s3", in: items), NSRect(x: 385, y: 108, width: 182.5, height: 64))
        XCTAssertEqual(contentHeight, 172)
    }

    func testCardsWrapIntoRowsAtNarrowWidth() {
        // 445 -> 2 columns, card width (445 - 10) / 2 = 217.5
        let (items, contentHeight) = L.items(for: sampleModel, width: 445)
        XCTAssertEqual(frame(of: "qc", in: items), NSRect(x: 0, y: 0, width: 217.5, height: 64))
        XCTAssertEqual(frame(of: "a", in: items), NSRect(x: 227.5, y: 0, width: 217.5, height: 64))
        XCTAssertEqual(frame(of: "b", in: items), NSRect(x: 0, y: 74, width: 217.5, height: 64))
        // header: 74 + 64 + 10 = 148; cards at 148 + 24 + 10 = 182 and 256
        XCTAssertEqual(items.first { $0.kind == .folderHeader("f1") }?.frame, NSRect(x: 0, y: 148, width: 445, height: 24))
        XCTAssertEqual(frame(of: "s1", in: items)?.minY, 182)
        XCTAssertEqual(frame(of: "s3", in: items), NSRect(x: 0, y: 256, width: 217.5, height: 64))
        XCTAssertEqual(contentHeight, 320)
    }

    func testEmptyFolderIsJustAHeaderAndEmptyTopLevelStartsAtZero() {
        let model = Model(topLevel: [], folders: [SAClaudeFavoriteFolder(id: "f", title: "A / B", cards: [])])
        let (items, contentHeight) = L.items(for: model, width: 760)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].frame, NSRect(x: 0, y: 0, width: 760, height: 24))
        XCTAssertEqual(contentHeight, 24)
        XCTAssertEqual(L.items(for: Model(topLevel: [], folders: []), width: 760).contentHeight, 0)
    }

    func testSecondFolderStartsOnANewRowAfterGap() {
        var model = sampleModel
        model.folders.append(SAClaudeFavoriteFolder(id: "f2", title: "Prod", cards: [card("p1", folder: "f2")]))
        let (items, contentHeight) = L.items(for: model, width: 760)
        XCTAssertEqual(items.first { $0.kind == .folderHeader("f2") }?.frame, NSRect(x: 0, y: 182, width: 760, height: 24))
        XCTAssertEqual(frame(of: "p1", in: items), NSRect(x: 0, y: 216, width: 182.5, height: 64))
        XCTAssertEqual(contentHeight, 280)
    }

    // MARK: Drop targets

    func testDropOverFolderHeaderIsInto() {
        let model = sampleModel
        let items = L.items(for: model, width: 760).items
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 300, y: 80), items: items, model: model), .into(folderID: "f1"))
    }

    func testDropOnLeftAndRightHalfOfACard() {
        let model = sampleModel
        let items = L.items(for: model, width: 760).items
        // card "a" spans x 192.5...375; midpoint 283.75
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 200, y: 30), items: items, model: model), .before(cardID: "a", folderID: nil))
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 370, y: 30), items: items, model: model), .before(cardID: "b", folderID: nil))
        // folder card "s2": right half -> before s3
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 360, y: 120), items: items, model: model), .before(cardID: "s3", folderID: "f1"))
    }

    func testDropOnRightHalfOfLastCardIsEndOfGroup() {
        let model = sampleModel
        let items = L.items(for: model, width: 760).items
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 560, y: 120), items: items, model: model), .endOf(folderID: "f1"))
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 560, y: 30), items: items, model: model), .endOf(folderID: nil))
        // right of the last card in a partial row
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 700, y: 120), items: items, model: model), .endOf(folderID: "f1"))
    }

    func testDropBelowAGroupIsEndOfThatGroup() {
        var model = sampleModel
        model.folders.append(SAClaudeFavoriteFolder(id: "f2", title: "Prod", cards: [card("p1", folder: "f2")]))
        let items = L.items(for: model, width: 760).items
        // gap between the top-level row (ends 64) and the f1 header (74)
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 100, y: 69), items: items, model: model), .endOf(folderID: nil))
        // gap between f1 cards (end 172) and the f2 header (182)
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 100, y: 177), items: items, model: model), .endOf(folderID: "f1"))
        // below everything
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 100, y: 500), items: items, model: model), .endOf(folderID: "f2"))
    }

    func testDropBelowAnEmptyFolderHeaderIsEndOfThatFolder() {
        let model = Model(topLevel: [card("qc", quick: true)], folders: [SAClaudeFavoriteFolder(id: "f", title: "Empty", cards: [])])
        let items = L.items(for: model, width: 760).items
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 10, y: 400), items: items, model: model), .endOf(folderID: "f"))
    }

    func testQuickConnectIsNeverATarget() {
        let model = sampleModel
        let items = L.items(for: model, width: 760).items
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 10, y: 30), items: items, model: model), .before(cardID: "a", folderID: nil))
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 170, y: 30), items: items, model: model), .before(cardID: "a", folderID: nil))

        let lonely = Model(topLevel: [card("qc", quick: true)], folders: [])
        let lonelyItems = L.items(for: lonely, width: 760).items
        XCTAssertEqual(L.dropTarget(at: NSPoint(x: 10, y: 30), items: lonelyItems, model: lonely), .endOf(folderID: nil))
    }

    func testDropOutsideTheGridIsNil() {
        let model = sampleModel
        let items = L.items(for: model, width: 760).items
        XCTAssertNil(L.dropTarget(at: NSPoint(x: 100, y: -5), items: items, model: model))
        XCTAssertNil(L.dropTarget(at: NSPoint(x: 100, y: 10), items: [], model: model))
    }

    // MARK: Reorder

    private func reorder(_ moving: [String], _ arrays: [String: [String]], to destination: String, at index: Int) -> [String: [String]] {
        var arrays = arrays
        SAClaudeFavoriteReorder.apply(moving: moving, from: &arrays, to: destination, at: index)
        return arrays
    }

    func testReorderWithinSameArrayForward() {
        let result = reorder(["B"], ["root": ["A", "B", "C", "D"]], to: "root", at: 4)
        XCTAssertEqual(result["root"], ["A", "C", "D", "B"])
        XCTAssertEqual(reorder(["B"], ["root": ["A", "B", "C", "D"]], to: "root", at: 3)["root"], ["A", "C", "B", "D"])
    }

    func testReorderWithinSameArrayBackward() {
        XCTAssertEqual(reorder(["D"], ["root": ["A", "B", "C", "D"]], to: "root", at: 0)["root"], ["D", "A", "B", "C"])
    }

    func testReorderToOwnPositionIsNoOp() {
        XCTAssertEqual(reorder(["B"], ["root": ["A", "B", "C"]], to: "root", at: 1)["root"], ["A", "B", "C"])
        XCTAssertEqual(reorder(["B"], ["root": ["A", "B", "C"]], to: "root", at: 2)["root"], ["A", "B", "C"])
    }

    func testReorderIntoAnotherFolder() {
        let result = reorder(["B"], ["root": ["A", "B", "C"], "f1": ["X", "Y"]], to: "f1", at: 1)
        XCTAssertEqual(result["root"], ["A", "C"])
        XCTAssertEqual(result["f1"], ["X", "B", "Y"])
    }

    func testReorderOutToTopLevel() {
        let result = reorder(["Y"], ["root": ["A", "B"], "f1": ["X", "Y"]], to: "root", at: 2)
        XCTAssertEqual(result["root"], ["A", "B", "Y"])
        XCTAssertEqual(result["f1"], ["X"])
    }

    func testReorderIntoEmptyOrMissingDestination() {
        let result = reorder(["A"], ["root": ["A", "B"], "f1": []], to: "f1", at: 0)
        XCTAssertEqual(result["f1"], ["A"])
        XCTAssertEqual(result["root"], ["B"])
        XCTAssertEqual(reorder(["A"], ["root": ["A", "B"]], to: "new", at: 0)["new"], ["A"])
    }

    func testReorderMultipleItemsKeepsTheirOrder() {
        // forward within one array: A and B land before D
        XCTAssertEqual(reorder(["A", "B"], ["root": ["A", "B", "C", "D"]], to: "root", at: 3)["root"], ["C", "A", "B", "D"])
        // backward within one array
        XCTAssertEqual(reorder(["C", "D"], ["root": ["A", "B", "C", "D"]], to: "root", at: 1)["root"], ["A", "C", "D", "B"])
        // from two different arrays into a third
        let result = reorder(["B", "X"], ["root": ["A", "B"], "f1": ["X", "Y"], "f2": ["P"]], to: "f2", at: 0)
        XCTAssertEqual(result["f2"], ["B", "X", "P"])
        XCTAssertEqual(result["root"], ["A"])
        XCTAssertEqual(result["f1"], ["Y"])
    }

    func testReorderClampsOutOfRangeIndex() {
        XCTAssertEqual(reorder(["A"], ["root": ["A", "B"], "f1": ["X"]], to: "f1", at: 9)["f1"], ["X", "A"])
    }

    // MARK: Model helpers

    func testCardIndexMapsFavouriteIDsToFlatPositions() {
        let model = sampleModel
        XCTAssertEqual(model.allCards.map(\.id), ["qc", "a", "b", "s1", "s2", "s3"])
        XCTAssertEqual(model.cardIndex(forFavoriteID: "qc"), 0)
        XCTAssertEqual(model.cardIndex(forFavoriteID: "b"), 2)
        XCTAssertEqual(model.cardIndex(forFavoriteID: "s2"), 4)
        XCTAssertNil(model.cardIndex(forFavoriteID: "nope"))
        XCTAssertEqual(model.cardID(at: 3), "s1")
        XCTAssertNil(model.cardID(at: 6))
        XCTAssertNil(model.cardID(at: -1))
    }

    // MARK: Summary and badge

    func testSummaries() {
        typealias S = SAClaudeFavoriteSummary
        XCTAssertEqual(S.summary(type: 0, user: "root", host: "db.local", port: "3306", socket: "", sshHost: ""), "root@db.local:3306")
        XCTAssertEqual(S.summary(type: 0, user: "", host: "db.local", port: "3306", socket: "", sshHost: ""), "db.local:3306")
        XCTAssertEqual(S.summary(type: 0, user: "root", host: "db.local", port: "", socket: "", sshHost: ""), "root@db.local")
        XCTAssertEqual(S.summary(type: 3, user: "iam", host: "x.rds.amazonaws.com", port: "3306", socket: "", sshHost: ""), "iam@x.rds.amazonaws.com:3306")
        XCTAssertEqual(S.summary(type: 4, user: "v", host: "h", port: "", socket: "", sshHost: ""), "v@h")
        XCTAssertEqual(S.summary(type: 1, user: "root", host: "", port: "", socket: "/tmp/mysql.sock", sshHost: ""), "root · /tmp/mysql.sock")
        XCTAssertEqual(S.summary(type: 1, user: "root", host: "", port: "", socket: "", sshHost: ""), "root · default socket")
        XCTAssertEqual(S.summary(type: 1, user: "", host: "", port: "", socket: "", sshHost: ""), "default socket")
        XCTAssertEqual(S.summary(type: 2, user: "root", host: "127.0.0.1", port: "3306", socket: "", sshHost: "bastion.example.com"), "root@127.0.0.1:3306 via bastion.example.com")
        XCTAssertEqual(S.summary(type: 2, user: "root", host: "127.0.0.1", port: "", socket: "", sshHost: ""), "root@127.0.0.1")
        XCTAssertEqual(S.summary(type: 0, user: "  root ", host: " h ", port: " 1 ", socket: "", sshHost: ""), "root@h:1")
    }

    func testBadges() {
        typealias S = SAClaudeFavoriteSummary
        XCTAssertEqual(S.badge(type: 0), "TCP/IP")
        XCTAssertEqual(S.badge(type: 1), "Socket")
        XCTAssertEqual(S.badge(type: 2), "SSH")
        XCTAssertEqual(S.badge(type: 3), "AWS IAM")
        XCTAssertEqual(S.badge(type: 4), "Vault")
        XCTAssertEqual(S.badge(type: 9), "")
    }

    // MARK: Model from the favourites tree

    private typealias Entry = SAClaudeFavoriteTreeEntry

    private func fav(_ id: String, host: String = "", type: Int = 0, colour: Int? = nil) -> Entry {
        Entry.favorite(id: id, name: id, type: type, user: "root", host: host, port: "3306", socket: "", sshHost: "", colorIndex: colour)
    }

    /// Top level: a, folder F (f1, nested folder G (g1), f2), b, empty folder E.
    private var sampleTree: [Entry] {
        [fav("a", host: "alpha.local", colour: 2),
         Entry.folder(id: "F", name: "Staging", children: [fav("f1", host: "s1.local"),
                                                            Entry.folder(id: "G", name: "EU", children: [fav("g1", host: "eu.local")]),
                                                            fav("f2", host: "s2.local")]),
         fav("b", host: "beta.local", type: 2, colour: -1),
         Entry.folder(id: "E", name: "Empty", children: [])]
    }

    private func makeModel(_ query: String = "") -> Model {
        Model.make(from: sampleTree, quickConnectName: "Quick connect", quickConnectSummary: "Fill in the panel below", query: query)
    }

    func testModelFromTreePutsQuickConnectAndTopLevelFirstThenFoldersDepthFirst() {
        let model = makeModel()
        XCTAssertEqual(model.topLevel.map(\.id), [Model.quickConnectID, "a", "b"])
        XCTAssertEqual(model.topLevel[0].isQuickConnect, true)
        XCTAssertEqual(model.topLevel[0].name, "Quick connect")
        XCTAssertEqual(model.topLevel[0].summary, "Fill in the panel below")
        XCTAssertEqual(model.folders.map(\.id), ["F", "G", "E"])
        XCTAssertEqual(model.folders.map(\.title), ["Staging", "Staging / EU", "Empty"])
        XCTAssertEqual(model.folders[0].cards.map(\.id), ["f1", "f2"])
        XCTAssertEqual(model.folders[0].cards.map(\.folderID), ["F", "F"])
        XCTAssertEqual(model.folders[1].cards.map(\.id), ["g1"])
        XCTAssertEqual(model.folders[1].cards[0].folderID, "G")
        XCTAssertEqual(model.folders[2].cards, [])
    }

    func testModelCardsCarrySummaryBadgeAndColour() {
        let model = makeModel()
        let a = model.topLevel[1]
        XCTAssertEqual(a.summary, "root@alpha.local:3306")
        XCTAssertEqual(a.badge, "TCP/IP")
        XCTAssertEqual(a.colorIndex, 2)
        XCTAssertNil(a.folderID)
        XCTAssertFalse(a.isQuickConnect)
        // A negative colour index means "no colour".
        XCTAssertEqual(model.topLevel[2].badge, "SSH")
        XCTAssertNil(model.topLevel[2].colorIndex)
    }

    func testModelFilterMatchesNameOrHostAndHidesFoldersWithoutMatches() {
        // "eu" matches g1's host only; Quick connect always stays.
        let model = makeModel("eu")
        XCTAssertEqual(model.topLevel.map(\.id), [Model.quickConnectID])
        XCTAssertEqual(model.folders.map(\.id), ["G"])
        XCTAssertEqual(model.folders[0].title, "Staging / EU")

        // Every token must match (name or host): "s2 local" → f2 only.
        let narrowed = makeModel("s2 local")
        XCTAssertEqual(narrowed.allCards.map(\.id), [Model.quickConnectID, "f2"])
        XCTAssertEqual(narrowed.folders.map(\.id), ["F"])

        // No match: only Quick connect, no folders.
        let none = makeModel("zzz")
        XCTAssertEqual(none.allCards.map(\.id), [Model.quickConnectID])
        XCTAssertEqual(none.folders, [])

        // Whitespace-only is no filter: empty folders stay.
        XCTAssertEqual(makeModel("   ").folders.map(\.id), ["F", "G", "E"])
    }

    func testModelFromEmptyTreeIsQuickConnectOnly() {
        let model = Model.make(from: [], quickConnectName: "Q", quickConnectSummary: "S", query: "")
        XCTAssertEqual(model.allCards.map(\.id), [Model.quickConnectID])
        XCTAssertEqual(model.folders, [])
    }

    func testCardsCarryTheirType() {
        let tree = [fav("ssh", host: "h", type: 2), fav("sock", type: 1), fav("tcp")]
        let model = Model.make(from: tree, quickConnectName: "Q", quickConnectSummary: "S", query: "")
        XCTAssertEqual(model.allCards.map(\.type), [0, 2, 1, 0])
        XCTAssertEqual(model.allCards.first { $0.id == "ssh" }?.type, 2)
        XCTAssertEqual(model.allCards.first { $0.id == "sock" }?.type, 1)
        XCTAssertEqual(model.topLevel[0].type, 0, "Quick connect")

        // Favourites in a folder carry theirs too.
        let nested = Model.make(from: [Entry.folder(id: "F", name: "F", children: [fav("v", type: 4)])],
                                quickConnectName: "Q", quickConnectSummary: "S", query: "")
        XCTAssertEqual(nested.folders[0].cards[0].type, 4)
    }

    func testCardIconPerType() {
        typealias Icon = SAClaudeFavoriteCardIcon
        XCTAssertEqual(Icon.icon(type: 0), .databaseGlyph)
        XCTAssertEqual(Icon.icon(type: 1), .symbol("powerplug"))
        XCTAssertEqual(Icon.icon(type: 2), .symbol("lock"))
        XCTAssertEqual(Icon.icon(type: 3), .symbol("cloud"))
        XCTAssertEqual(Icon.icon(type: 4), .symbol("key"))
        XCTAssertEqual(Icon.icon(type: 9), .databaseGlyph)
        XCTAssertEqual(Icon.icon(type: -1), .databaseGlyph)
    }

    // MARK: Drop target → tree position

    private func destination(_ target: L.DropTarget, moving id: String) -> L.TreeDestination? {
        L.treeDestination(for: target, moving: id, in: sampleTree)
    }

    func testBeforeACardIsThatCardsIndexAmongItsParentsRealChildren() {
        // F's real children are [f1, G, f2]: f2 is at index 2 even though it's the second card.
        XCTAssertEqual(destination(.before(cardID: "f2", folderID: "F"), moving: "a"), L.TreeDestination(folderID: "F", index: 2))
        // Top level is [a, F, b, E]: b is at index 2.
        XCTAssertEqual(destination(.before(cardID: "b", folderID: nil), moving: "g1"), L.TreeDestination(folderID: nil, index: 2))
        XCTAssertEqual(destination(.before(cardID: "g1", folderID: "G"), moving: "a"), L.TreeDestination(folderID: "G", index: 0))
    }

    func testEndOfAGroupIsItsRealChildCount() {
        XCTAssertEqual(destination(.endOf(folderID: nil), moving: "f1"), L.TreeDestination(folderID: nil, index: 4))
        XCTAssertEqual(destination(.endOf(folderID: "F"), moving: "a"), L.TreeDestination(folderID: "F", index: 3))
        XCTAssertEqual(destination(.endOf(folderID: "E"), moving: "a"), L.TreeDestination(folderID: "E", index: 0))
    }

    func testIntoAFolderIsItsStart() {
        XCTAssertEqual(destination(.into(folderID: "G"), moving: "a"), L.TreeDestination(folderID: "G", index: 0))
        XCTAssertEqual(destination(.into(folderID: "E"), moving: "f2"), L.TreeDestination(folderID: "E", index: 0))
    }

    func testDropsThatLeaveTheCardInPlaceAreNil() {
        // Before itself, before its next sibling, at the end of its own group when it is last, at the start when first.
        XCTAssertNil(destination(.before(cardID: "f2", folderID: "F"), moving: "f2"))
        XCTAssertNil(L.treeDestination(for: .before(cardID: "y", folderID: nil), moving: "x", in: [fav("x"), fav("y")]))
        XCTAssertNil(destination(.endOf(folderID: "G"), moving: "g1"))
        XCTAssertNil(destination(.into(folderID: "F"), moving: "f1"))
        // Top level [a, F, b, E] shows "QC a b": a on its own right half (before b) or b on its own right half
        // (end of the top level) only shifts them past folders, which the grid shows apart — no move.
        XCTAssertNil(destination(.before(cardID: "b", folderID: nil), moving: "a"))
        XCTAssertNil(destination(.endOf(folderID: nil), moving: "b"))
        // F is [f1, G, f2]: f1 to the end only passes G.
        XCTAssertNil(L.treeDestination(for: .before(cardID: "f2", folderID: "F"), moving: "f1", in: sampleTree))
    }

    func testDropsThatReorderFavouritesInTheSameParentMove() {
        // Plain move down past the card's own index among contiguous favourites: before z is index 2.
        XCTAssertEqual(L.treeDestination(for: .before(cardID: "z", folderID: nil), moving: "x", in: [fav("x"), fav("y"), fav("z")]),
                       L.TreeDestination(folderID: nil, index: 2))
        XCTAssertEqual(L.treeDestination(for: .before(cardID: "x", folderID: nil), moving: "z", in: [fav("x"), fav("y"), fav("z")]),
                       L.TreeDestination(folderID: nil, index: 0))
        // a past b (with folders between) changes the favourites' order.
        XCTAssertEqual(destination(.endOf(folderID: nil), moving: "a"), L.TreeDestination(folderID: nil, index: 4))
        XCTAssertEqual(destination(.into(folderID: "F"), moving: "f2"), L.TreeDestination(folderID: "F", index: 0))
    }

    func testUnknownCardsFoldersAndQuickConnectAreNil() {
        XCTAssertNil(destination(.before(cardID: "nope", folderID: nil), moving: "a"))
        XCTAssertNil(destination(.endOf(folderID: "nope"), moving: "a"))
        XCTAssertNil(destination(.into(folderID: "nope"), moving: "a"))
        XCTAssertNil(destination(.endOf(folderID: nil), moving: "nope"))
        XCTAssertNil(destination(.endOf(folderID: nil), moving: Model.quickConnectID))
        // A folder is not a card.
        XCTAssertNil(destination(.endOf(folderID: nil), moving: "F"))
    }

    // MARK: Keyboard neighbours

    func testLeftAndRightFollowDisplayOrder() {
        let (items, _) = L.items(for: sampleModel, width: 760) // 4 columns: qc a b / f1: s1 s2 s3
        XCTAssertEqual(L.neighbour(of: "b", .right, items: items), "s1")
        XCTAssertEqual(L.neighbour(of: "s1", .left, items: items), "b")
        XCTAssertEqual(L.neighbour(of: "qc", .left, items: items), nil)
        XCTAssertEqual(L.neighbour(of: "s3", .right, items: items), nil)
    }

    func testUpAndDownPickTheNearestCardInTheNextRow() {
        let (items, _) = L.items(for: sampleModel, width: 445) // 2 columns: qc a / b ; s1 s2 / s3
        XCTAssertEqual(L.neighbour(of: "qc", .down, items: items), "b")
        XCTAssertEqual(L.neighbour(of: "a", .down, items: items), "b")
        XCTAssertEqual(L.neighbour(of: "b", .down, items: items), "s1")
        XCTAssertEqual(L.neighbour(of: "s2", .down, items: items), "s3")
        XCTAssertEqual(L.neighbour(of: "s1", .up, items: items), "b")
        XCTAssertEqual(L.neighbour(of: "b", .up, items: items), "qc")
        XCTAssertEqual(L.neighbour(of: "s2", .up, items: items), "b")
        XCTAssertNil(L.neighbour(of: "a", .up, items: items))
        XCTAssertNil(L.neighbour(of: "s3", .down, items: items))
    }

    func testArrowsFromAFolderHeaderMoveRelativeToThatFolder() {
        let (items, _) = L.items(for: sampleModel, width: 760) // qc a b / f1: s1 s2 s3
        XCTAssertEqual(L.neighbour(of: "f1", .down, items: items), "s1")
        XCTAssertEqual(L.neighbour(of: "f1", .right, items: items), "s1")
        XCTAssertEqual(L.neighbour(of: "f1", .up, items: items), "b")
        XCTAssertEqual(L.neighbour(of: "f1", .left, items: items), "b")

        // An empty folder: down goes on to the next group's first card; a header at the very end has nothing below.
        let model = Model(topLevel: [card("qc", quick: true)],
                          folders: [SAClaudeFavoriteFolder(id: "e", title: "Empty", cards: []),
                                    SAClaudeFavoriteFolder(id: "f", title: "F", cards: [card("f1", folder: "f")]),
                                    SAClaudeFavoriteFolder(id: "z", title: "Z", cards: [])])
        let (more, _) = L.items(for: model, width: 760)
        XCTAssertEqual(L.neighbour(of: "e", .down, items: more), "f1")
        XCTAssertEqual(L.neighbour(of: "e", .up, items: more), "qc")
        XCTAssertNil(L.neighbour(of: "z", .down, items: more))
        XCTAssertEqual(L.neighbour(of: "z", .up, items: more), "f1")
    }

    func testNoCurrentCardMovesToTheFirst() {
        let (items, _) = L.items(for: sampleModel, width: 760)
        XCTAssertEqual(L.neighbour(of: nil, .down, items: items), "qc")
        XCTAssertEqual(L.neighbour(of: "gone", .right, items: items), "qc")
        XCTAssertNil(L.neighbour(of: nil, .down, items: []))
    }
}
