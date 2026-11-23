//
//  SAClaudeConnectionPanelLayout.swift
//  Sequel Ace
//
//  Pure model for the Claude connection panel: which section each form field belongs to, the frames of the
//  header, section titles, rows, Advanced disclosure and action row at a given width, the "has a non-default
//  advanced value" check and the header subtitle. Shared with Unit Tests; no app types.
//

import AppKit

/// Matches the connection tab index / the `type` binding.
enum SAClaudeConnectionType: Int {
    case tcpip = 0, socket, ssh, awsIAM, vault
}

enum SAClaudeConnectionSection: Equatable, Hashable {
    /// The panel header (the connection name); never laid out in a column.
    case header
    case server, signIn, sshTunnel, vault, advanced
}

enum SAClaudeConnectionRowKind: Equatable {
    case field, checkbox, checkboxPair, colour, note(height: CGFloat), button, fileRow, comboWithButton
}

struct SAClaudeConnectionRowSpec: Equatable {
    var id: String
    var label: String?
    var kind: SAClaudeConnectionRowKind
    var section: SAClaudeConnectionSection
}

// MARK: - Classification

enum SAClaudeConnectionClassifier {
    /// Section + order for a binding key path (or a synthetic id such as "colour") on a given type;
    /// nil = unknown, so the type keeps its XIB layout.
    static func placement(keyPath: String, type: SAClaudeConnectionType) -> (section: SAClaudeConnectionSection, order: Int)? {
        // Fields present on every type. The name is the panel's title, edited in the header.
        switch keyPath {
        case "name": return (.header, 0)
        case "colour": return (.advanced, 1)
        case "timeZone": return (.advanced, 2)
        case "allowDataLocalInfile": return (.advanced, 3)
        default: break
        }

        switch type {
        case .tcpip:
            switch keyPath {
            case "host": return (.server, 0)
            case "port": return (.server, 1)
            case "database": return (.server, 2)
            case "user": return (.signIn, 0)
            case "password": return (.signIn, 1)
            default: return sslPlacement(keyPath)
            }
        case .socket:
            switch keyPath {
            case "socket": return (.server, 0)
            case "database": return (.server, 1)
            case "user": return (.signIn, 0)
            case "password": return (.signIn, 1)
            default: return sslPlacement(keyPath)
            }
        case .ssh:
            switch keyPath {
            case "host": return (.server, 0)
            case "port": return (.server, 1)
            case "database": return (.server, 2)
            case "sshRemoteSocketPath": return (.server, 3)
            case "user": return (.signIn, 0)
            case "password": return (.signIn, 1)
            case "sshHost": return (.sshTunnel, 0)
            case "sshUser": return (.sshTunnel, 1)
            case "sshPassword", "sshKeyLocation": return (.sshTunnel, 2)
            case "sshPort": return (.sshTunnel, 3)
            default: return sslPlacement(keyPath)
            }
        case .awsIAM:
            switch keyPath {
            case "host": return (.server, 0)
            case "port": return (.server, 1)
            case "database": return (.server, 2)
            case "user": return (.signIn, 0)
            case "password": return (.signIn, 1)
            case "awsProfile": return (.signIn, 2)
            case "awsRegion": return (.signIn, 3)
            case "awsSSLNote": return (.advanced, 6)
            default: return nil
            }
        case .vault:
            switch keyPath {
            case "host": return (.server, 0)
            case "port": return (.server, 1)
            case "database": return (.server, 2)
            case "vaultHost": return (.vault, 0)
            case "vaultMount": return (.vault, 1)
            case "vaultCredentialsRole": return (.vault, 2)
            case "vaultPort": return (.vault, 3)
            case "vaultOIDCMount": return (.vault, 4)
            default: return sslPlacement(keyPath)
            }
        }
    }

    /// Advanced rows shared by every type except AWS IAM (clear-text plugin and the SSL block).
    private static func sslPlacement(_ keyPath: String) -> (section: SAClaudeConnectionSection, order: Int)? {
        switch keyPath {
        case "enableClearTextPlugin": return (.advanced, 4)
        case "useSSL", "requestServerPublicKey": return (.advanced, 5)
        case "sslKeyFileLocation": return (.advanced, 6)
        case "sslCertificateFileLocation": return (.advanced, 7)
        case "sslCACertFileLocation": return (.advanced, 8)
        default: return nil
        }
    }

    /// The binding key paths a type must have to be laid out; if any is missing the type keeps its XIB layout.
    /// The SSL file paths and `requestServerPublicKey` are not required (they only show while Require SSL is on).
    static func requiredKeyPaths(for type: SAClaudeConnectionType) -> Set<String> {
        var keys: Set<String> = ["name", "allowDataLocalInfile", "database", "host", "port", "user", "password"]
        switch type {
        case .tcpip:
            keys.formUnion(["enableClearTextPlugin", "useSSL"])
        case .socket:
            keys.subtract(["host", "port"])
            keys.formUnion(["socket", "enableClearTextPlugin", "useSSL"])
        case .ssh:
            keys.formUnion(["sshRemoteSocketPath", "sshHost", "sshUser", "sshPassword", "sshKeyLocation", "sshPort",
                            "enableClearTextPlugin", "useSSL"])
        case .awsIAM:
            keys.formUnion(["awsProfile", "awsRegion"])
        case .vault:
            keys.subtract(["user", "password"])
            keys.formUnion(["vaultHost", "vaultMount", "vaultCredentialsRole", "vaultPort", "vaultOIDCMount",
                            "enableClearTextPlugin", "useSSL"])
        }
        return keys
    }
}

// MARK: - Layout

enum SAClaudeConnectionPanelLayout {
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 32
    static let headerGap: CGFloat = 12
    static let rowHeight: CGFloat = 32
    static let sectionTitleHeight: CGFloat = 18
    static let sectionGap: CGFloat = 10
    static let labelWidth: CGFloat = 104
    static let labelGap: CGFloat = 8
    static let columnGap: CGFloat = 24
    static let disclosureHeight: CGFloat = 28
    static let actionRowHeight: CGFloat = 32
    static let actionGap: CGFloat = 12
    static let oneColumnBelow: CGFloat = 620
    static let radius: CGFloat = 12

    struct RowFrame: Equatable {
        var id: String
        var label: NSRect?
        var control: NSRect
    }

    struct Frames: Equatable {
        var header: NSRect
        var tabs: NSRect
        var sectionTitles: [SAClaudeConnectionSection: NSRect]
        var rows: [RowFrame]
        var disclosure: NSRect
        var actionRow: NSRect
        var height: CGFloat
    }

    static func height(for kind: SAClaudeConnectionRowKind) -> CGFloat {
        if case .note(let height) = kind { return height }
        return rowHeight
    }

    /// Lays out the rows for a type at `width` (the panel's full width). Rows within a section keep the given order.
    /// Advanced rows are laid out only when `advancedOpen`; `.header` rows never are (the header rect holds them). Unflipped coordinates (origin bottom-left); the layout is
    /// computed from the panel top and mirrored at the end.
    static func frames(type: SAClaudeConnectionType, rows: [SAClaudeConnectionRowSpec], width: CGFloat,
                       advancedOpen: Bool, tabsWidth: CGFloat) -> Frames {
        let contentWidth = width - 2 * padding
        let twoColumns = width >= oneColumnBelow
        let columnWidth = twoColumns ? (contentWidth - columnGap) / 2 : contentWidth
        let rightX = padding + columnWidth + columnGap
        let labelOffset = labelWidth + labelGap

        func specs(in section: SAClaudeConnectionSection) -> [SAClaudeConnectionRowSpec] {
            rows.filter { $0.section == section }
        }

        // Top-down results; mirrored into bottom-left coordinates at the end.
        var titles: [SAClaudeConnectionSection: NSRect] = [:]
        var placed: [(id: String, label: NSRect?, control: NSRect)] = []

        func place(_ row: SAClaudeConnectionRowSpec, x: CGFloat, y: CGFloat, width w: CGFloat) {
            let h = height(for: row.kind)
            let hasLabel: Bool
            switch row.kind {
            case .checkbox, .checkboxPair, .note: hasLabel = false
            default: hasLabel = true
            }
            let label = hasLabel ? NSRect(x: x, y: y, width: labelWidth, height: h) : nil
            let control = NSRect(x: x + labelOffset, y: y, width: w - labelOffset, height: h)
            placed.append((row.id, label, control))
        }

        /// Stacks sections (title + rows) in a column starting at `top`; returns the bottom edge.
        func stack(_ sections: [SAClaudeConnectionSection], x: CGFloat, top: CGFloat) -> CGFloat {
            var y = top
            var first = true
            for section in sections {
                let sectionRows = specs(in: section)
                if sectionRows.isEmpty { continue }
                if !first { y += sectionGap }
                first = false
                titles[section] = NSRect(x: x, y: y, width: columnWidth, height: sectionTitleHeight)
                y += sectionTitleHeight
                for row in sectionRows {
                    place(row, x: x, y: y, width: columnWidth)
                    y += height(for: row.kind)
                }
            }
            return y
        }

        let headerTop = padding
        let columnsTop = headerTop + headerHeight + headerGap

        // Column block.
        let leftSections: [SAClaudeConnectionSection] = type == .ssh ? [.server, .signIn] : [.server]
        let rightSections: [SAClaudeConnectionSection] = type == .ssh ? [.sshTunnel] : [.signIn, .sshTunnel, .vault]
        var y: CGFloat
        if twoColumns {
            let leftBottom = stack(leftSections, x: padding, top: columnsTop)
            let rightBottom = stack(rightSections, x: rightX, top: columnsTop)
            y = max(leftBottom, rightBottom)
        } else {
            y = stack([.server, .signIn, .sshTunnel, .vault], x: padding, top: columnsTop)
        }

        // Disclosure.
        y += sectionGap
        let disclosureTop = y
        y += disclosureHeight

        // Advanced block: no title (the disclosure is its title); rows flow in two columns when available.
        if advancedOpen {
            let advancedRows = specs(in: .advanced)
            if !advancedRows.isEmpty {
                y += sectionGap
                let perLine = twoColumns ? 2 : 1
                var index = 0
                while index < advancedRows.count {
                    let line = advancedRows[index ..< min(index + perLine, advancedRows.count)]
                    for (offset, row) in line.enumerated() {
                        place(row, x: offset == 0 ? padding : rightX, y: y, width: columnWidth)
                    }
                    y += line.map { height(for: $0.kind) }.max() ?? rowHeight
                    index += perLine
                }
            }
        }

        // Action row.
        y += actionGap
        let actionTop = y
        y += actionRowHeight
        let totalHeight = y + padding

        func flip(_ r: NSRect) -> NSRect {
            NSRect(x: r.minX, y: totalHeight - r.minY - r.height, width: r.width, height: r.height)
        }

        let tabsRect = NSRect(x: width - padding - tabsWidth, y: headerTop, width: tabsWidth, height: headerHeight)
        let headerRect = NSRect(x: padding, y: headerTop, width: max(0, contentWidth - tabsWidth), height: headerHeight)

        return Frames(
            header: flip(headerRect),
            tabs: flip(tabsRect),
            sectionTitles: titles.mapValues(flip),
            rows: placed.map { RowFrame(id: $0.id, label: $0.label.map(flip), control: flip($0.control)) },
            disclosure: flip(NSRect(x: padding, y: disclosureTop, width: contentWidth, height: disclosureHeight)),
            actionRow: flip(NSRect(x: padding, y: actionTop, width: contentWidth, height: actionRowHeight)),
            height: totalHeight)
    }
}

// MARK: - Advanced state

struct SAClaudeConnectionAdvancedState {
    var useSSL: Bool
    var allowDataLocalInfile: Bool
    var enableClearTextPlugin: Bool
    var requestServerPublicKey: Bool
    var timeZoneIsServerDefault: Bool
    var sslFiles: [String?]
}

enum SAClaudeConnectionAdvanced {
    /// True when any Advanced setting differs from its default (so the disclosure opens by default).
    static func hasNonDefault(_ s: SAClaudeConnectionAdvancedState) -> Bool {
        s.useSSL || s.allowDataLocalInfile || s.enableClearTextPlugin || s.requestServerPublicKey
            || !s.timeZoneIsServerDefault
            || s.sslFiles.contains { !($0 ?? "").isEmpty }
    }
}

// MARK: - Subtitle

enum SAClaudeConnectionSummary {
    static func subtitle(type: SAClaudeConnectionType, host: String, port: String, socket: String, sshHost: String) -> String {
        let hostPort = "\(host.isEmpty ? "localhost" : host):\(port.isEmpty ? "3306" : port)"
        switch type {
        case .tcpip, .awsIAM, .vault:
            return "MySQL · \(hostPort)"
        case .socket:
            return "Socket · \(socket.isEmpty ? "default" : socket)"
        case .ssh:
            return "SSH · \(hostPort)" + (sshHost.isEmpty ? "" : " via \(sshHost)")
        }
    }
}
