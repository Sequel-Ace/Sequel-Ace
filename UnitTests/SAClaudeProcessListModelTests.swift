//
//  SAClaudeProcessListModelTests.swift
//  Unit Tests
//

import XCTest

private func p(_ id: Int64, user: String = "app", host: String = "10.0.0.5:5123", db: String? = "shop", command: String = "Query",
               time: Int = 3, state: String? = "executing", info: String? = "SELECT 1") -> SAClaudeProcess {
    SAClaudeProcess(id: id, user: user, host: host, db: db, command: command, time: time, state: state, info: info)
}

private func sleeper(_ id: Int64, user: String = "app", time: Int = 100) -> SAClaudeProcess {
    p(id, user: user, command: "Sleep", time: time, state: "", info: nil)
}

final class SAClaudeProcessListModelTests: XCTestCase {

    /// A server with each kind of connection: a lock wait, a long query, a short one, two sleepers, a replica thread,
    /// and the list's own connection (#900).
    private var server: [SAClaudeProcess] {
        [p(1, user: "kunal", time: 2, state: "Waiting for table metadata lock", info: "ALTER TABLE orders ADD x INT"),
         p(2, time: 400, state: "Sending data", info: "SELECT * FROM big"),
         p(3, user: "kunal", time: 4, info: "UPDATE stock SET n = n - 1"),
         sleeper(4, user: "kunal"),
         sleeper(5, time: 9),
         p(6, user: "system user", host: "", db: nil, command: "Connect", time: 90000, state: "Waiting for source to send event", info: nil),
         p(900, user: "kunal", time: 0, state: "init", info: "SHOW FULL PROCESSLIST")]
    }

    private func input(_ filter: SAClaudeProcessListFilter = .all, search: String = "", threshold: Int = 30,
                       own: Int64 = 900) -> SAClaudeProcessListModel.Input {
        .init(processes: server, threshold: threshold, filter: filter, search: search, user: "kunal", ownConnectionId: own)
    }

    // MARK: Chips, counts, search

    func testChipCountsLeaveOutTheListsOwnConnection() {
        let contents = SAClaudeProcessListModel.contents(input())
        XCTAssertEqual(contents.counts, SAClaudeProcessListCounts(all: 6, needsAttention: 2, running: 1, idle: 3, mine: 3))
        XCTAssertFalse(contents.rows.contains { $0.id == 900 })
    }

    func testOwnConnectionShownOnTheSharedFallback() {
        // No dedicated connection (id 0): the row running SHOW FULL PROCESSLIST is the window's own and stays.
        let contents = SAClaudeProcessListModel.contents(input(own: 0))
        XCTAssertTrue(contents.rows.contains { $0.id == 900 })
        XCTAssertEqual(contents.counts.all, 7)
        XCTAssertEqual(contents.counts.mine, 4)
    }

    func testEachChipShowsItsGroupInTriageOrder() {
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(.all)).rows.map(\.id), [2, 1, 3, 4, 5, 6])
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(.needsAttention)).rows.map(\.id), [2, 1])
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(.running)).rows.map(\.id), [3])
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(.idle)).rows.map(\.id), [4, 5, 6])
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(.mine)).rows.map(\.id), [1, 3, 4])
    }

    func testChipAndSearchCombine() {
        // "stock" matches #3's query only; counts follow the search, the chip narrows the rows.
        let running = SAClaudeProcessListModel.contents(input(.running, search: "STOCK"))
        XCTAssertEqual(running.rows.map(\.id), [3])
        XCTAssertEqual(running.counts, SAClaudeProcessListCounts(all: 1, needsAttention: 0, running: 1, idle: 0, mine: 1))
        let attention = SAClaudeProcessListModel.contents(input(.needsAttention, search: "stock"))
        XCTAssertTrue(attention.rows.isEmpty)
        // Search covers user, host, database, state and id too.
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(search: "metadata")).rows.map(\.id), [1])
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(.idle, search: "system")).rows.map(\.id), [6])
        // The own connection never matches, even by its query.
        XCTAssertTrue(SAClaudeProcessListModel.contents(input(search: "PROCESSLIST")).rows.isEmpty)
    }

    func testThresholdMovesLongQueriesIntoNeedsAttention() {
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(threshold: 300)).counts.needsAttention, 2)   // 400 s > 300 s
        XCTAssertEqual(SAClaudeProcessListModel.contents(input(threshold: 10)).counts.needsAttention, 2)
        let tight = SAClaudeProcessListModel.contents(.init(processes: [p(7, time: 11)], threshold: 10))
        XCTAssertEqual(tight.rows.first?.group, .needsAttention)
        let loose = SAClaudeProcessListModel.contents(.init(processes: [p(7, time: 11)], threshold: 30))
        XCTAssertEqual(loose.rows.first?.group, .running)
    }

    // MARK: Row texts

    func testRowTexts() {
        let rows = SAClaudeProcessListModel.contents(input()).rows
        let replica = rows.first { $0.id == 6 }!
        XCTAssertTrue(replica.isBackground)
        XCTAssertEqual(replica.group, .idle)
        XCTAssertEqual(replica.stateText, "Background · Waiting for source to send event")
        XCTAssertNil(replica.preview)
        let idle = rows.first { $0.id == 4 }!
        XCTAssertEqual(idle.stateText, "Sleep")
        XCTAssertNil(idle.preview)
        XCTAssertEqual(idle.timeText, "1m 40s")
        XCTAssertEqual(rows.first { $0.id == 2 }!.timeText, "6m 40s")
    }

    func testPreviewIsTheFirstTwoLines() {
        XCTAssertEqual(SAClaudeProcessListModel.preview("\n\n   SELECT a,\n  b\nFROM t\nWHERE x"), "SELECT a,\n  b…")
        XCTAssertEqual(SAClaudeProcessListModel.preview("SELECT 1"), "SELECT 1")
        XCTAssertEqual(SAClaudeProcessListModel.preview("SELECT 1\nFROM dual\n"), "SELECT 1\nFROM dual")
        XCTAssertNil(SAClaudeProcessListModel.preview(nil))
        XCTAssertNil(SAClaudeProcessListModel.preview("  \n "))
        let long = "SELECT " + String(repeating: "column_name, ", count: 2000) + "x FROM t"
        let preview = SAClaudeProcessListModel.preview(long)!
        XCTAssertEqual(preview.count, SAClaudeProcessListModel.previewCharacterLimit + 1)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    // MARK: Selection by connection id

    func testSelectionIsKeptByIdWhenRowsReorder() {
        var selection = SAClaudeProcessListSelection()
        let before = SAClaudeProcessListModel.contents(input()).rows   // [2, 1, 3, 4, 5, 6]
        selection.userSelected(ids: [3], lead: 3, in: before)
        XCTAssertEqual(selection.indexes(in: before), IndexSet([2]))

        // #3 now needs attention and #8 arrives: the rows reorder.
        var later = server
        later[2] = p(3, user: "kunal", time: 45, info: "UPDATE stock SET n = n - 1")
        later.append(p(8, time: 600, info: "SELECT SLEEP(600)"))
        let after = SAClaudeProcessListModel.contents(.init(processes: later, threshold: 30, user: "kunal", ownConnectionId: 900)).rows
        selection.refresh(with: later)
        XCTAssertEqual(after.map(\.id), [8, 2, 3, 1, 4, 5, 6])
        XCTAssertEqual(selection.indexes(in: after), IndexSet([2]))
        XCTAssertEqual(selection.detail?.killTarget, 3)
    }

    func testFilteredOutSelectionComesBackAndThePanelStays() {
        var selection = SAClaudeProcessListSelection()
        let all = SAClaudeProcessListModel.contents(input()).rows
        selection.userSelected(ids: [5], lead: 5, in: all)
        let running = SAClaudeProcessListModel.contents(input(.running)).rows
        XCTAssertTrue(selection.indexes(in: running).isEmpty)
        XCTAssertEqual(selection.detail?.id, 5, "the panel keeps the connection while its row is filtered out")
        XCTAssertEqual(selection.indexes(in: all), IndexSet([4]))
    }

    func testPanelFollowsTheLeadRowAndClearsWithTheSelection() {
        var selection = SAClaudeProcessListSelection()
        let rows = SAClaudeProcessListModel.contents(input()).rows
        selection.userSelected(ids: [2, 1], lead: 1, in: rows)
        XCTAssertEqual(selection.detail?.id, 1)
        selection.userSelected(ids: [], lead: nil, in: rows)
        XCTAssertNil(selection.detail)
        XCTAssertTrue(selection.ids.isEmpty)
    }

    func testReselectingTheShownConnectionKeepsItsSnapshot() {
        var selection = SAClaudeProcessListSelection()
        let rows = SAClaudeProcessListModel.contents(input()).rows
        selection.userSelected(ids: [3], lead: 3, in: rows)
        var later = server
        later[2] = p(3, user: "kunal", time: 1, info: "DELETE FROM carts")
        selection.refresh(with: later)
        XCTAssertTrue(selection.detail!.hasMovedOn)
        let laterRows = SAClaudeProcessListModel.contents(.init(processes: later, threshold: 30, ownConnectionId: 900)).rows
        selection.userSelected(ids: [3], lead: 3, in: laterRows)
        XCTAssertEqual(selection.detail?.shownQuery, "UPDATE stock SET n = n - 1")
    }

    // MARK: Detail snapshot and kill safety

    func testDetailKeepsTheQueryWhenTheConnectionMovesOn() {
        var detail = SAClaudeProcessDetailState(process: p(4812, time: 5, info: "UPDATE stock SET n = n - 1"))
        detail.update(from: [p(4812, time: 9, info: "UPDATE stock SET n = n - 1")])
        XCTAssertFalse(detail.hasMovedOn)
        XCTAssertEqual(detail.shown.time, 9, "the same query: the snapshot follows the connection")

        detail.update(from: [p(4812, time: 1, info: "SELECT * FROM orders")])
        XCTAssertTrue(detail.hasMovedOn)
        XCTAssertEqual(detail.shownQuery, "UPDATE stock SET n = n - 1")
        XCTAssertEqual(detail.killTarget, 4812)

        detail.showCurrent()
        XCTAssertFalse(detail.hasMovedOn)
        XCTAssertEqual(detail.shownQuery, "SELECT * FROM orders")
    }

    func testDetailOfAConnectionThatWentIdleKeepsTheQuery() {
        var detail = SAClaudeProcessDetailState(process: p(7, info: "SELECT SLEEP(60)"))
        detail.update(from: [sleeper(7)])
        XCTAssertTrue(detail.hasMovedOn)
        XCTAssertEqual(detail.shownQuery, "SELECT SLEEP(60)")
    }

    func testIdleDetailFollowsTheConnection() {
        var detail = SAClaudeProcessDetailState(process: sleeper(7))
        XCTAssertNil(detail.shownQuery)
        detail.update(from: [p(7, info: "SELECT 2")])
        XCTAssertFalse(detail.hasMovedOn, "nothing to keep: an idle snapshot follows")
        XCTAssertEqual(detail.shownQuery, "SELECT 2")
    }

    func testEndedConnectionDisablesBothKills() {
        var detail = SAClaudeProcessDetailState(process: p(4812, info: "UPDATE stock SET n = n - 1"))
        detail.update(from: [p(17, info: "SELECT 1")])
        XCTAssertTrue(detail.hasEnded)
        XCTAssertNil(detail.killTarget)
        XCTAssertFalse(detail.hasMovedOn)
        XCTAssertEqual(detail.shownQuery, "UPDATE stock SET n = n - 1", "the query can still be read and copied")
    }

    func testKillTargetsTheShownIdNotARowIndex() {
        // The panel shows #3 at row 2; a refresh puts #8 at row 2. The kill still names #3 with the query shown.
        var selection = SAClaudeProcessListSelection()
        selection.userSelected(ids: [3], lead: 3, in: SAClaudeProcessListModel.contents(input()).rows)
        let later = [p(8, time: 600, info: "SELECT SLEEP(600)"), p(9, time: 500, info: "SELECT 9")] + server
        selection.refresh(with: later)
        let rows = SAClaudeProcessListModel.contents(.init(processes: later, threshold: 30, ownConnectionId: 900)).rows
        XCTAssertNotEqual(rows[2].id, 3)
        XCTAssertEqual(selection.detail?.killTarget, 3)
        XCTAssertEqual(selection.detail?.shownQuery, "UPDATE stock SET n = n - 1")
    }

    /// Review I1: the right-click target is captured as the menu opens; a refresh that reorders the rows before the
    /// command fires doesn't move it to whichever connection now sits at the clicked row.
    func testRightClickKillKeepsTheConnectionCapturedWhenTheMenuOpened() {
        let rows = SAClaudeProcessListModel.contents(input()).rows       // [2, 1, 3, 4, 5, 6]
        let clickedRow = 2
        XCTAssertEqual(rows[clickedRow].id, 3)
        let target = SAClaudeProcessListContextTarget(clickedId: rows[clickedRow].id, selectedIds: [5], rows: rows)

        // While the menu is open: #8 and #9 arrive at the top — the rows shift down under the clicked row.
        let later = server + [p(8, time: 600, info: "SELECT SLEEP(600)"), p(9, time: 500, info: "SELECT SLEEP(500)")]
        let laterRows = SAClaudeProcessListModel.contents(.init(processes: later, threshold: 30, ownConnectionId: 900)).rows
        XCTAssertNotEqual(laterRows[clickedRow].id, 3)

        let kill = target.killTarget(in: later)
        XCTAssertEqual(kill?.id, 3)
        XCTAssertEqual(kill?.shownQuery, "UPDATE stock SET n = n - 1")

        // Ended by the time the command fires: nothing to kill (the items are disabled).
        XCTAssertNil(target.killTarget(in: later.filter { $0.id != 3 }))
    }

    func testRightClickOnTheSelectionTargetsItAndKillNeedsOne() {
        let rows = SAClaudeProcessListModel.contents(input()).rows
        let target = SAClaudeProcessListContextTarget(clickedId: 1, selectedIds: [2, 1], rows: rows)
        XCTAssertEqual(target.ids, [2, 1])
        XCTAssertNil(target.killTarget(in: server), "Kill acts on exactly one connection")
        let idle = SAClaudeProcessListContextTarget(clickedId: 4, selectedIds: [], rows: rows)
        XCTAssertEqual(idle.killTarget(in: server)?.id, 4)
        XCTAssertNil(idle.killTarget(in: server)?.shownQuery)
    }

    /// Review M3: only a sleeping client is an "idle connection"; other connections without query text say "no query".
    func testEmptyQueryText() {
        let rows = SAClaudeProcessListModel.contents(input()).rows
        XCTAssertEqual(rows.first { $0.id == 4 }?.emptyQueryText, "idle connection")
        XCTAssertEqual(rows.first { $0.id == 6 }?.emptyQueryText, "no query")
        XCTAssertEqual(SAClaudeProcessListModel.emptyQueryText(p(9, command: "Binlog Dump GTID", info: nil)), "no query")
        XCTAssertEqual(SAClaudeProcessListModel.emptyQueryText(p(9, command: "Query", info: nil)), "no query")
    }

    func testRightClickCommandTargets() {
        XCTAssertEqual(SAClaudeProcessListModel.commandTargets(clickedId: 5, selectedIds: [1, 2]), [5])
        XCTAssertEqual(SAClaudeProcessListModel.commandTargets(clickedId: 2, selectedIds: [1, 2]), [1, 2])
        XCTAssertEqual(SAClaudeProcessListModel.commandTargets(clickedId: nil, selectedIds: [1, 2]), [1, 2])
        XCTAssertEqual(SAClaudeProcessListModel.commandTargets(clickedId: nil, selectedIds: []), [])
    }
}
