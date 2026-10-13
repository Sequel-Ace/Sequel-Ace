//
//  SAClaudeFavoriteCardLayout.swift
//  Sequel Ace
//
//  Pure model and geometry for the connection screen's favourite cards: the card/folder/grid model, the
//  column count and item frames at a given width, drop-target resolution, the reorder algorithm on ID
//  arrays (mirrors the outline drop in SAFavoritesListDataSource) and the card summary/badge strings.
//  Shared with Unit Tests; no app types.
//

import AppKit

// MARK: - Model

struct SAClaudeFavoriteCard: Equatable {
    var id: String
    var isQuickConnect: Bool
    var name: String
    var summary: String
    var badge: String
    var colorIndex: Int?
    var folderID: String?
}

struct SAClaudeFavoriteFolder: Equatable {
    var id: String
    /// "Parent / Child" for nested folders.
    var title: String
    var cards: [SAClaudeFavoriteCard]
}

struct SAClaudeFavoriteGridModel: Equatable {
    /// Quick connect first, then the favourites that are not in a folder.
    var topLevel: [SAClaudeFavoriteCard]
    var folders: [SAClaudeFavoriteFolder]

    /// Every card in display order: top level, then each folder's cards. The flat position of a card is
    /// its index in this array.
    var allCards: [SAClaudeFavoriteCard] { topLevel + folders.flatMap(\.cards) }

    /// Flat position of the card with this ID (Quick connect is position 0 when present).
    func cardIndex(forFavoriteID id: String) -> Int? {
        allCards.firstIndex { $0.id == id }
    }

    /// ID of the card at a flat position, `nil` when out of range.
    func cardID(at index: Int) -> String? {
        let cards = allCards
        return cards.indices.contains(index) ? cards[index].id : nil
    }
}

// MARK: - Geometry

enum SAClaudeFavoriteCardLayout {
    static let cardHeight: CGFloat = 64
    static let gap: CGFloat = 10
    static let minCardWidth: CGFloat = 180
    static let maxColumns = 4
    static let folderHeaderHeight: CGFloat = 24
    static let radius: CGFloat = 10
    static let visibleCardRows = 3

    static func columns(for width: CGFloat) -> Int {
        max(1, min(maxColumns, Int(floor((width + gap) / (minCardWidth + gap)))))
    }

    struct Item: Equatable {
        enum Kind: Equatable {
            case card(String)
            case folderHeader(String)
        }

        var kind: Kind
        var frame: NSRect
    }

    /// Frames in flipped coordinates (y down from the grid's top; the grid view is flipped). Top-level
    /// cards flow in rows; each folder then starts on a new row with a full-width header followed by its
    /// cards. `gap` separates rows and precedes each folder header (except at the very top).
    static func items(for model: SAClaudeFavoriteGridModel, width: CGFloat) -> (items: [Item], contentHeight: CGFloat) {
        let cols = columns(for: width)
        let cardWidth = (width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        var items: [Item] = []
        var y: CGFloat = 0

        func flow(_ cards: [SAClaudeFavoriteCard]) {
            for (i, card) in cards.enumerated() {
                let col = i % cols
                let row = i / cols
                let frame = NSRect(x: CGFloat(col) * (cardWidth + gap),
                                   y: y + CGFloat(row) * (cardHeight + gap),
                                   width: cardWidth, height: cardHeight)
                items.append(Item(kind: .card(card.id), frame: frame))
            }
            let rows = (cards.count + cols - 1) / cols
            if rows > 0 { y += CGFloat(rows) * cardHeight + CGFloat(rows - 1) * gap }
        }

        flow(model.topLevel)
        for folder in model.folders {
            if y > 0 { y += gap }
            items.append(Item(kind: .folderHeader(folder.id), frame: NSRect(x: 0, y: y, width: width, height: folderHeaderHeight)))
            y += folderHeaderHeight
            if !folder.cards.isEmpty {
                y += gap
                flow(folder.cards)
            }
        }
        return (items, y)
    }

    static func visibleHeight(contentHeight: CGFloat) -> CGFloat {
        let cap = CGFloat(visibleCardRows) * cardHeight + CGFloat(visibleCardRows - 1) * gap + folderHeaderHeight
        return min(contentHeight, cap)
    }

    // MARK: Drop targets

    enum DropTarget: Equatable {
        case before(cardID: String, folderID: String?)
        case endOf(folderID: String?)
        case into(folderID: String)
    }

    /// Where a drop at `point` (grid coordinates, flipped) would land. Folder header: into that folder.
    /// Left half of a card: before it; right half: before the next card of the same group, else the end of
    /// that group. Gaps and space below a group's last row: the end of that group. Quick connect is never
    /// a target; dropping on it means "first among the top-level favourites". `nil` outside the grid.
    static func dropTarget(at point: NSPoint, items: [Item], model: SAClaudeFavoriteGridModel) -> DropTarget? {
        guard !items.isEmpty, point.y >= 0, point.x >= 0 else { return nil }

        var frames: [String: NSRect] = [:]
        var headers: [String: NSRect] = [:]
        for item in items {
            switch item.kind {
            case .card(let id): frames[id] = item.frame
            case .folderHeader(let id): headers[id] = item.frame
            }
        }

        // Groups in display order with the y where each begins.
        struct Group {
            var folderID: String?
            var cards: [SAClaudeFavoriteCard]
            var startY: CGFloat
            var header: NSRect?
        }
        var groups: [Group] = []
        if !model.topLevel.isEmpty { groups.append(Group(folderID: nil, cards: model.topLevel, startY: 0, header: nil)) }
        for folder in model.folders {
            guard let header = headers[folder.id] else { continue }
            groups.append(Group(folderID: folder.id, cards: folder.cards, startY: header.minY, header: header))
        }
        guard !groups.isEmpty else { return nil }

        // The group whose span contains the point (the last group extends downward without limit).
        var index = 0
        for (i, g) in groups.enumerated() where point.y >= g.startY { index = i }
        let group = groups[index]

        if let header = group.header, let folderID = group.folderID {
            if point.y < header.maxY { return .into(folderID: folderID) }
        }

        let cardFrames = group.cards.compactMap { card in frames[card.id].map { (card, $0) } }
        guard let lastRowMaxY = cardFrames.map({ $0.1.maxY }).max() else { return .endOf(folderID: group.folderID) }

        // Between a folder header and its first row.
        if let firstRowMinY = cardFrames.map({ $0.1.minY }).min(), point.y < firstRowMinY, let folderID = group.folderID {
            return .into(folderID: folderID)
        }
        if point.y >= lastRowMaxY { return .endOf(folderID: group.folderID) }

        // The row at (or, in the gap between rows, above) the point, then the card in it at (or left of) x.
        let rowMinY = cardFrames.map { $0.1.minY }.filter { $0 <= point.y }.max() ?? 0
        let rowCards = cardFrames.filter { $0.1.minY == rowMinY }.sorted { $0.1.minX < $1.1.minX }
        let hit = rowCards.last { $0.1.minX <= point.x } ?? rowCards[0]
        let (card, frame) = hit

        let cards = group.cards
        let position = cards.firstIndex { $0.id == card.id } ?? 0
        let next: SAClaudeFavoriteCard? = position + 1 < cards.count ? cards[position + 1] : nil

        func after() -> DropTarget {
            if let next { return .before(cardID: next.id, folderID: group.folderID) }
            return .endOf(folderID: group.folderID)
        }

        if card.isQuickConnect { return after() }
        if point.x < frame.midX { return .before(cardID: card.id, folderID: group.folderID) }
        return after()
    }
}

// MARK: - Reorder

enum SAClaudeFavoriteReorder {
    /// Pure reorder on ID arrays: moves `moving` (in the given order) into `arrays[destination]` at
    /// `index` (an index in the destination before the move), removing each from whichever array holds it.
    /// Mirrors the outline drop in `SAFavoritesListDataSource`: an item already in the destination is
    /// removed first and, when it preceded the insertion point, the insertion index shifts down by one.
    /// An `index` past the end appends. Every moved item ends up in `destination`, which is created when
    /// missing.
    static func apply(moving: [String], from arrays: inout [String: [String]], to destination: String, at index: Int) {
        var target = arrays[destination] ?? []
        var insertIndex = index

        for id in moving {
            var newIndex = insertIndex
            if let oldIndex = target.firstIndex(of: id) {
                target.remove(at: oldIndex)
                if insertIndex > oldIndex { newIndex -= 1 }
            } else {
                for key in arrays.keys where key != destination {
                    arrays[key]?.removeAll { $0 == id }
                }
            }
            newIndex = max(0, min(newIndex, target.count))
            target.insert(id, at: newIndex)
            insertIndex = newIndex + 1
        }
        arrays[destination] = target
    }
}

// MARK: - Summary and badge

enum SAClaudeFavoriteSummary {
    /// Connection type integers match `SAClaudeConnectionType` / the `type` binding.
    static func summary(type: Int, user: String, host: String, port: String, socket: String, sshHost: String) -> String {
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let socket = socket.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)

        func address() -> String {
            var text = user.isEmpty ? "" : "\(user)@"
            text += host
            if !port.isEmpty { text += ":\(port)" }
            return text
        }

        switch SAClaudeConnectionType(rawValue: type) {
        case .socket:
            let path = socket.isEmpty ? "default socket" : socket
            return user.isEmpty ? path : "\(user) · \(path)"
        case .ssh:
            return sshHost.isEmpty ? address() : "\(address()) via \(sshHost)"
        case .tcpip, .awsIAM, .vault, .none:
            return address()
        }
    }

    static func badge(type: Int) -> String {
        switch SAClaudeConnectionType(rawValue: type) {
        case .tcpip: return "TCP/IP"
        case .socket: return "Socket"
        case .ssh: return "SSH"
        case .awsIAM: return "AWS IAM"
        case .vault: return "Vault"
        case .none: return ""
        }
    }
}
