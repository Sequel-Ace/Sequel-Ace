//
//  SAClaudeFavoriteCardLayout.swift
//  Sequel Ace
//
//  Pure model and geometry for the connection screen's favourite cards: the card/folder/grid model, the
//  column count and item frames at a given width, drop-target resolution, the reorder algorithm on ID
//  arrays (mirrors the outline drop in SAFavoritesListDataSource) and the card summary/badge strings; the grid
//  model built from a value copy of the favourites tree, drop targets translated to tree positions and arrow-key
//  movement.
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
    /// The favourite's connection type (`SAClaudeConnectionType` raw value); Quick connect is 0.
    var type = 0
}

/// The glyph in a card's colour circle.
enum SAClaudeFavoriteCardIcon: Equatable {
    /// The app's own database icon.
    case databaseGlyph
    /// An SF Symbol, by name.
    case symbol(String)

    /// TCP/IP and any unknown type show the database glyph; the other connection types a symbol of their own.
    static func icon(type: Int) -> SAClaudeFavoriteCardIcon {
        switch SAClaudeConnectionType(rawValue: type) {
        case .socket: return .symbol("powerplug")
        case .ssh: return .symbol("lock")
        case .awsIAM: return .symbol("cloud")
        case .vault: return .symbol("key")
        case .tcpip, .none: return .databaseGlyph
        }
    }
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

// MARK: - Model from the favourites tree

/// A value copy of the favourites tree below the outline's section group, so the grid model and drop
/// translation can be built and tested without `SPTreeNode`. The app builds it from the live tree (one
/// entry per node, with the node's ID) and maps IDs back to nodes.
struct SAClaudeFavoriteTreeEntry: Equatable {
    var id: String
    var name: String
    var type = 0
    var user = ""
    var host = ""
    var port = ""
    var socket = ""
    var sshHost = ""
    var colorIndex: Int?
    /// `nil` for a favourite; a folder's children (possibly empty) otherwise.
    var children: [SAClaudeFavoriteTreeEntry]?

    var isFolder: Bool { children != nil }

    static func favorite(id: String, name: String, type: Int, user: String, host: String, port: String, socket: String,
                         sshHost: String, colorIndex: Int?) -> SAClaudeFavoriteTreeEntry {
        SAClaudeFavoriteTreeEntry(id: id, name: name, type: type, user: user, host: host, port: port, socket: socket,
                                  sshHost: sshHost, colorIndex: colorIndex, children: nil)
    }

    static func folder(id: String, name: String, children: [SAClaudeFavoriteTreeEntry]) -> SAClaudeFavoriteTreeEntry {
        SAClaudeFavoriteTreeEntry(id: id, name: name, children: children)
    }
}

extension SAClaudeFavoriteGridModel {
    /// The Quick connect card's ID (it has no node in the favourites tree).
    static let quickConnectID = "quickConnect"

    /// The grid for `entries` (the children of the favourites section group): Quick connect, then the
    /// top-level favourites, then every folder depth-first ("Parent / Child") with its own favourites.
    /// With an active `query` (`SAFavoriteSearchMatcher`: every token in the name or host), only matching
    /// favourites show and folders without a matching favourite of their own hide; Quick connect stays.
    static func make(from entries: [SAClaudeFavoriteTreeEntry], quickConnectName: String, quickConnectSummary: String,
                     query: String) -> SAClaudeFavoriteGridModel {
        let matcher = SAFavoriteSearchMatcher(query: query)

        func cards(in children: [SAClaudeFavoriteTreeEntry], folderID: String?) -> [SAClaudeFavoriteCard] {
            children.filter { !$0.isFolder && matcher.matches(name: $0.name, host: $0.host) }.map { entry in
                SAClaudeFavoriteCard(id: entry.id, isQuickConnect: false, name: entry.name,
                                     summary: SAClaudeFavoriteSummary.summary(type: entry.type, user: entry.user, host: entry.host,
                                                                              port: entry.port, socket: entry.socket, sshHost: entry.sshHost),
                                     badge: SAClaudeFavoriteSummary.badge(type: entry.type),
                                     colorIndex: entry.colorIndex.flatMap { $0 >= 0 ? $0 : nil }, folderID: folderID,
                                     type: entry.type)
            }
        }

        var folders: [SAClaudeFavoriteFolder] = []
        func addFolders(in children: [SAClaudeFavoriteTreeEntry], path: [String]) {
            for folder in children where folder.isFolder {
                let title = (path + [folder.name]).joined(separator: " / ")
                let folderCards = cards(in: folder.children ?? [], folderID: folder.id)
                if !matcher.isActive || !folderCards.isEmpty {
                    folders.append(SAClaudeFavoriteFolder(id: folder.id, title: title, cards: folderCards))
                }
                addFolders(in: folder.children ?? [], path: path + [folder.name])
            }
        }
        addFolders(in: entries, path: [])

        let quickConnect = SAClaudeFavoriteCard(id: quickConnectID, isQuickConnect: true, name: quickConnectName,
                                                summary: quickConnectSummary, badge: "", colorIndex: nil, folderID: nil)
        return SAClaudeFavoriteGridModel(topLevel: [quickConnect] + cards(in: entries, folderID: nil), folders: folders)
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

    // MARK: Card content

    /// Inset of a card's content from its left and right edges.
    static let contentPadding: CGFloat = 12
    static let circleSize: CGFloat = 28
    static let circleGap: CGFloat = 10
    /// Space between the summary text and the badge pill that ends its row.
    static let badgeGap: CGFloat = 8

    /// Widths of a card's name and summary lines. Both start after the icon circle; the name takes the card's
    /// full width up to the right padding, the badge pill (`pillWidth`, nil without a badge) sits at the right end
    /// of the summary row, so only the summary gives way to it.
    static func textWidths(cardWidth: CGFloat, pillWidth: CGFloat?) -> (name: CGFloat, summary: CGFloat) {
        let name = max(0, cardWidth - contentPadding - (contentPadding + circleSize + circleGap))
        guard let pillWidth else { return (name, name) }
        return (name, max(0, name - pillWidth - badgeGap))
    }

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

// MARK: - Drop translation and keyboard movement

extension SAClaudeFavoriteCardLayout {
    /// A position in the real favourites tree: a folder (`nil` = the top level, i.e. the favourites section
    /// group) and an index among ALL its children (folders and favourites interleaved) — what the shared move
    /// helper takes.
    struct TreeDestination: Equatable {
        var folderID: String?
        var index: Int
    }

    /// Translates a grid drop target into a tree position. Grid positions can't be used directly: the top-level
    /// row starts with Quick connect, and a folder's cards leave out its subfolders. `.before(card)` is that
    /// card's index in its parent's children, `.endOf(folder)` the parent's child count and `.into(folder)` its
    /// start. `nil` when the target or the moving favourite isn't in `entries`, or when the move wouldn't change
    /// what the grid shows: within the same parent, the order of its favourites (folders interleave with them in
    /// the tree but are shown apart) stays the same — such a drop must not save or reset the sort.
    static func treeDestination(for target: DropTarget, moving id: String,
                                in entries: [SAClaudeFavoriteTreeEntry]) -> TreeDestination? {
        func children(of folderID: String?) -> [SAClaudeFavoriteTreeEntry]? {
            guard let folderID else { return entries }
            func find(_ list: [SAClaudeFavoriteTreeEntry]) -> [SAClaudeFavoriteTreeEntry]? {
                for entry in list where entry.isFolder {
                    if entry.id == folderID { return entry.children }
                    if let found = find(entry.children ?? []) { return found }
                }
                return nil
            }
            return find(entries)
        }
        func location(of id: String, in list: [SAClaudeFavoriteTreeEntry], folderID: String?) -> (folderID: String?, index: Int)? {
            for (index, entry) in list.enumerated() {
                if entry.id == id { return entry.isFolder ? nil : (folderID, index) }
                if entry.isFolder, let found = location(of: id, in: entry.children ?? [], folderID: entry.id) { return found }
            }
            return nil
        }

        guard let origin = location(of: id, in: entries, folderID: nil) else { return nil }
        let destination: TreeDestination
        switch target {
        case .before(let cardID, let folderID):
            guard let siblings = children(of: folderID), let index = siblings.firstIndex(where: { $0.id == cardID }) else { return nil }
            destination = TreeDestination(folderID: folderID, index: index)
        case .endOf(let folderID):
            guard let siblings = children(of: folderID) else { return nil }
            destination = TreeDestination(folderID: folderID, index: siblings.count)
        case .into(let folderID):
            guard children(of: folderID) != nil else { return nil }
            destination = TreeDestination(folderID: folderID, index: 0)
        }
        if destination.folderID == origin.folderID, let siblings = children(of: origin.folderID) {
            // The parent's children after the move, with the helper's down-shift when moving past the old index.
            var moved = siblings
            let entry = moved.remove(at: origin.index)
            moved.insert(entry, at: min(destination.index > origin.index ? destination.index - 1 : destination.index, moved.count))
            func favouriteOrder(_ list: [SAClaudeFavoriteTreeEntry]) -> [String] { list.filter { !$0.isFolder }.map(\.id) }
            if favouriteOrder(moved) == favouriteOrder(siblings) { return nil }
        }
        return destination
    }

    enum MoveDirection {
        case left, right, up, down
    }

    /// The card an arrow key moves to from `id`: left / right step through the display order; up / down go to the
    /// nearest card (by centre x) in the closest row above / below, folder headers skipped. From a folder header,
    /// down / right go to the first card after it (its own first card) and up / left to the last card before it
    /// (the previous group's last). The first card when `id` is `nil` or not shown; `nil` at an edge.
    static func neighbour(of id: String?, _ direction: MoveDirection, items: [Item]) -> String? {
        let cards: [(id: String, frame: NSRect)] = items.compactMap {
            if case .card(let cardID) = $0.kind { return (cardID, $0.frame) }
            return nil
        }
        guard let first = cards.first else { return nil }
        if let id, let header = items.firstIndex(where: { $0.kind == .folderHeader(id) }) {
            func cardID(_ item: Item) -> String? {
                if case .card(let cardID) = item.kind { return cardID }
                return nil
            }
            switch direction {
            case .down, .right: return items[(header + 1)...].lazy.compactMap(cardID).first
            case .up, .left: return items[..<header].reversed().lazy.compactMap(cardID).first
            }
        }
        guard let id, let position = cards.firstIndex(where: { $0.id == id }) else { return first.id }
        let current = cards[position].frame

        switch direction {
        case .left:
            return position > 0 ? cards[position - 1].id : nil
        case .right:
            return position + 1 < cards.count ? cards[position + 1].id : nil
        case .up, .down:
            let rows = cards.map(\.frame.minY).filter { direction == .up ? $0 < current.minY : $0 > current.minY }
            guard let row = direction == .up ? rows.max() : rows.min() else { return nil }
            return cards.filter { $0.frame.minY == row }
                .min { abs($0.frame.midX - current.midX) < abs($1.frame.midX - current.midX) }?.id
        }
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
