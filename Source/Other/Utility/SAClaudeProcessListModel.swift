//
//  SAClaudeProcessListModel.swift
//  Sequel Ace
//
//  The Process List window's view logic, pure so it is tested: what the list shows for a filter chip, a search and a
//  threshold (rows, sorted; chip counts; the list's own connection left out), the row texts, the selection kept by
//  connection id across refreshes, and the detail panel's snapshot of the connection it shows. Shared with the Unit
//  Tests target.
//

import Foundation

/// The filter chips across the Process List's header.
enum SAClaudeProcessListFilter: Int, CaseIterable, Equatable {
    case all, needsAttention, running, idle, mine
}

/// The live count on each chip.
struct SAClaudeProcessListCounts: Equatable {
    var all = 0
    var needsAttention = 0
    var running = 0
    var idle = 0
    var mine = 0

    func count(for filter: SAClaudeProcessListFilter) -> Int {
        switch filter {
        case .all: return all
        case .needsAttention: return needsAttention
        case .running: return running
        case .idle: return idle
        case .mine: return mine
        }
    }
}

/// One row of the list, ready to show.
struct SAClaudeProcessListRow: Equatable {
    let process: SAClaudeProcess
    let group: SAClaudeProcessGroup
    /// A replication or system thread: shown in the Idle group, labelled "Background".
    let isBackground: Bool
    /// The meta line's state: the state (or, without one, the command); background threads say so first.
    let stateText: String
    let timeText: String
    /// The start of the query, for the row's two lines; nil for an idle connection (no query).
    let preview: String?

    var id: Int64 { process.id }
}

/// What the list shows: its rows, in order, and the chip counts.
struct SAClaudeProcessListContents: Equatable {
    var rows: [SAClaudeProcessListRow]
    var counts: SAClaudeProcessListCounts
}

enum SAClaudeProcessListModel {
    /// The row shows at most this much of a query (two wrapped lines never need more): long queries are clipped before
    /// they reach the text system.
    static let previewCharacterLimit = 400
    static let previewLineLimit = 2

    struct Input: Equatable {
        var processes: [SAClaudeProcess]
        var threshold: Int
        var filter: SAClaudeProcessListFilter = .all
        var search: String = ""
        /// The window's connection user, for Mine.
        var user: String = ""
        /// The list's own connection (its row runs SHOW FULL PROCESSLIST), left out of the rows and the counts; 0 when
        /// the list shares the window's connection.
        var ownConnectionId: Int64 = 0
    }

    /// The rows for the chip and the search (both apply), sorted (needs attention, running, idle; longest first), and
    /// the counts of every chip for the search. The list's own connection is never shown or counted.
    static func contents(_ input: Input) -> SAClaudeProcessListContents {
        var counts = SAClaudeProcessListCounts()
        var shown: [SAClaudeProcess] = []
        shown.reserveCapacity(input.processes.count)
        for process in input.processes where !isOwnConnection(process, ownConnectionId: input.ownConnectionId) {
            guard SAClaudeProcessClassifier.matches(process, search: input.search) else { continue }
            let group = SAClaudeProcessClassifier.group(process, threshold: input.threshold)
            let mine = SAClaudeProcessClassifier.isMine(process, user: input.user)
            counts.all += 1
            switch group {
            case .needsAttention: counts.needsAttention += 1
            case .running: counts.running += 1
            case .idle: counts.idle += 1
            }
            if mine { counts.mine += 1 }
            if passes(input.filter, group: group, mine: mine) { shown.append(process) }
        }
        let rows = SAClaudeProcessClassifier.sorted(shown, threshold: input.threshold).map { row(for: $0, threshold: input.threshold) }
        return SAClaudeProcessListContents(rows: rows, counts: counts)
    }

    static func passes(_ filter: SAClaudeProcessListFilter, group: SAClaudeProcessGroup, mine: Bool) -> Bool {
        switch filter {
        case .all: return true
        case .needsAttention: return group == .needsAttention
        case .running: return group == .running
        case .idle: return group == .idle
        case .mine: return mine
        }
    }

    static func isOwnConnection(_ process: SAClaudeProcess, ownConnectionId: Int64) -> Bool {
        ownConnectionId != 0 && process.id == ownConnectionId
    }

    static func row(for process: SAClaudeProcess, threshold: Int) -> SAClaudeProcessListRow {
        let background = SAClaudeProcessClassifier.isBackground(process)
        return SAClaudeProcessListRow(process: process,
                                      group: SAClaudeProcessClassifier.group(process, threshold: threshold),
                                      isBackground: background,
                                      stateText: stateText(process, isBackground: background),
                                      timeText: SAClaudeProcessClassifier.timeText(process.time),
                                      preview: preview(process.info))
    }

    /// "Background · Waiting for source to send event" for a background thread; else the state, or the command when
    /// the state is empty ("Sleep").
    static func stateText(_ process: SAClaudeProcess, isBackground: Bool) -> String {
        let state = (process.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = state.isEmpty ? process.command : state
        guard isBackground else { return base }
        let label = backgroundLabel
        return base.isEmpty ? label : label + " · " + base
    }

    static var backgroundLabel: String {
        NSLocalizedString("Background", comment: "process list : label of a replication or system thread")
    }

    /// The query's first lines for the row: leading blank lines and spaces dropped; at most `previewLineLimit` lines
    /// and `previewCharacterLimit` characters, with "…" when anything was cut. nil when there is no query.
    static func preview(_ info: String?) -> String? {
        guard let info else { return nil }
        let trimmed = info.drop { $0.isWhitespace || $0.isNewline }
        guard !trimmed.isEmpty else { return nil }
        var result = ""
        var lines = 0
        var clipped = false
        var count = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character.isNewline {
                lines += 1
                if lines >= previewLineLimit {
                    clipped = trimmed[trimmed.index(after: index)...].contains { !$0.isWhitespace }
                    break
                }
            }
            if count >= previewCharacterLimit {
                clipped = true
                break
            }
            result.append(character)
            count += 1
            index = trimmed.index(after: index)
        }
        while let last = result.last, last.isWhitespace || last.isNewline { result.removeLast() }
        return clipped ? result + "…" : result
    }

    /// The rows (by index) to select: those whose connection id is selected.
    static func selectionIndexes(for ids: Set<Int64>, in rows: [SAClaudeProcessListRow]) -> IndexSet {
        guard !ids.isEmpty else { return IndexSet() }
        var indexes = IndexSet()
        for (index, row) in rows.enumerated() where ids.contains(row.id) { indexes.insert(index) }
        return indexes
    }

    /// The connections a right-click command acts on: the selection when the clicked row is part of it (or no row was
    /// clicked, as with the Edit menu's Copy), else only the clicked row.
    static func commandTargets(clickedId: Int64?, selectedIds: [Int64]) -> [Int64] {
        guard let clickedId, !selectedIds.contains(clickedId) else { return selectedIds }
        return [clickedId]
    }
}

/// The detail panel's connection: its id, and the snapshot it shows. A refresh that finds the connection running the
/// same query (or the snapshot had none) brings the snapshot up to date; one that finds it running another query, or
/// idle, keeps the snapshot so it can still be read and copied ("moved on"); one that no longer lists it marks it ended,
/// which disables both Kill buttons.
struct SAClaudeProcessDetailState: Equatable {
    let id: Int64
    /// What the panel shows.
    private(set) var shown: SAClaudeProcess
    /// The connection in the latest list; nil once it has ended.
    private(set) var current: SAClaudeProcess?

    init(process: SAClaudeProcess) {
        id = process.id
        shown = process
        current = process
    }

    var hasEnded: Bool { current == nil }

    /// The connection now runs something other than the query shown (or went idle).
    var hasMovedOn: Bool {
        guard let current, Self.hasQuery(shown) else { return false }
        return SAClaudeProcessKillDecision.queryChanged(shown: shown.info, current: current.info)
    }

    /// The id the Kill buttons act on; nil (both disabled) once the connection has ended.
    var killTarget: Int64? { hasEnded ? nil : id }

    /// The query the panel shows: Copy query, Open in editor and Kill query's check all use it.
    var shownQuery: String? { Self.hasQuery(shown) ? shown.info : nil }

    mutating func update(from processes: [SAClaudeProcess]) {
        current = processes.first { $0.id == id }
        guard let current else { return }
        if !Self.hasQuery(shown) || !SAClaudeProcessKillDecision.queryChanged(shown: shown.info, current: current.info) {
            shown = current
        }
    }

    /// "Show current": the snapshot becomes what the connection runs now.
    mutating func showCurrent() {
        if let current { shown = current }
    }

    private static func hasQuery(_ process: SAClaudeProcess) -> Bool {
        !(process.info ?? "").isEmpty
    }
}

/// The list's selection, kept by connection id (never by row index): the selected ids, and the detail panel's
/// connection, which follows the most recently selected row and stays while that row is filtered out or the
/// connection ends.
struct SAClaudeProcessListSelection: Equatable {
    private(set) var ids: [Int64] = []
    private(set) var detail: SAClaudeProcessDetailState?

    /// The user changed the selection: `ids` in row order, `lead` the row the table calls selected (its last
    /// clicked). An empty selection clears the panel. Picking the connection the panel already shows keeps its
    /// snapshot.
    mutating func userSelected(ids newIds: [Int64], lead: Int64?, in rows: [SAClaudeProcessListRow]) {
        ids = newIds
        guard let lead = lead ?? newIds.last, newIds.contains(lead) else {
            detail = nil
            return
        }
        if detail?.id == lead { return }
        if let row = rows.first(where: { $0.id == lead }) {
            detail = SAClaudeProcessDetailState(process: row.process)
        }
    }

    /// A refresh: the ids stay selected (rows that ended simply aren't shown); the panel's connection is updated.
    mutating func refresh(with processes: [SAClaudeProcess]) {
        detail?.update(from: processes)
    }

    mutating func showCurrent() {
        detail?.showCurrent()
    }

    mutating func clear() {
        ids = []
        detail = nil
    }

    func indexes(in rows: [SAClaudeProcessListRow]) -> IndexSet {
        SAClaudeProcessListModel.selectionIndexes(for: Set(ids), in: rows)
    }
}
