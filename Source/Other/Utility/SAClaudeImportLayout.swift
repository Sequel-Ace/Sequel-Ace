//
//  SAClaudeImportLayout.swift
//  Sequel Ace
//
//  Frames for the Claude Import flow: the file-open-panel accessory strip (format switcher, encoding, CSV grid /
//  SQL pop-up) and the field-mapping sheet (header, two cards, footer) plus the import-method segment state.
//  Pure geometry, shared with Unit Tests. Coordinates are AppKit's (origin bottom-left).
//

import AppKit

enum SAClaudeImportAccessoryLayout {
    static let margin: CGFloat = 16
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 12
    static let switcherHeight: CGFloat = 26
    static let encodingWidth: CGFloat = 200
    static let rowHeight: CGFloat = 24
    static let checkboxRowHeight: CGFloat = 20
    static let labelWidth: CGFloat = 110
    static let fieldWidth: CGFloat = 64
    static let fieldHeight: CGFloat = 22
    static let columnGap: CGFloat = 24
    static let rowGap: CGFloat = 6
    static let sqlPopUpWidth: CGFloat = 220

    enum Format { case csv, sql }

    struct Frames: Equatable {
        var height: CGFloat
        var formatSwitcher: NSRect
        var encodingLabel: NSRect
        var encoding: NSRect
        /// CSV only (zero for SQL).
        var firstLine: NSRect
        /// Order: fields terminated, fields enclosed, lines terminated, fields escaped.
        var csvLabels: [NSRect]
        var csvFields: [NSRect]
        /// SQL only (zero for CSV).
        var sqlLabel: NSRect
        var sqlPopUp: NSRect
    }

    static func frames(width W: CGFloat, format: Format, switcherWidth: CGFloat, encodingLabelWidth: CGFloat) -> Frames {
        let m = margin
        let H: CGFloat = format == .csv
            ? topPadding + switcherHeight + 10 + checkboxRowHeight + 8 + rowHeight + rowGap + rowHeight + bottomPadding   // 142
            : topPadding + switcherHeight + 10 + rowHeight + bottomPadding                                                  // 84
        let switcherY = H - topPadding - switcherHeight
        let switcher = NSRect(x: m, y: switcherY, width: switcherWidth, height: switcherHeight)
        let encoding = NSRect(x: W - m - encodingWidth, y: switcherY + 1, width: encodingWidth, height: 24)
        let encodingLabel = NSRect(x: encoding.minX - 8 - encodingLabelWidth, y: encoding.minY + 4, width: encodingLabelWidth, height: 16)
        var f = Frames(height: H, formatSwitcher: switcher, encodingLabel: encodingLabel, encoding: encoding,
                       firstLine: .zero, csvLabels: [], csvFields: [], sqlLabel: .zero, sqlPopUp: .zero)
        switch format {
        case .csv:
            f.firstLine = NSRect(x: m, y: switcherY - 10 - checkboxRowHeight, width: W - 2 * m, height: checkboxRowHeight)
            let columnWidth = ((W - 2 * m - columnGap) / 2).rounded(.down)
            let row1 = f.firstLine.minY - 8 - rowHeight, row2 = row1 - rowGap - rowHeight
            for (rowY, column) in [(row1, 0), (row1, 1), (row2, 0), (row2, 1)] {
                let x = m + CGFloat(column) * (columnWidth + columnGap)
                f.csvLabels.append(NSRect(x: x, y: rowY + 4, width: labelWidth, height: 16))
                f.csvFields.append(NSRect(x: x + labelWidth + 8, y: rowY + 1, width: fieldWidth, height: fieldHeight))
            }
        case .sql:
            let rowY = switcherY - 10 - rowHeight
            f.sqlLabel = NSRect(x: m, y: rowY + 4, width: labelWidth, height: 16)
            f.sqlPopUp = NSRect(x: m + labelWidth + 8, y: rowY, width: sqlPopUpWidth, height: rowHeight)
        }
        return f
    }
}

enum SAClaudeImportMapperLayout {
    static let margin: CGFloat = 16
    static let gap: CGFloat = 10
    static let headerHeight: CGFloat = 28
    static let footerHeight: CGFloat = 28
    static let cardPadding: CGFloat = 12
    static let titleHeight: CGFloat = 16
    static let titleGap: CGFloat = 6
    static let optionsMinWidth: CGFloat = 300
    static let optionsShare: CGFloat = 0.4
    static let targetWidth: CGFloat = 200
    static let nameFieldWidth: CGFloat = 180
    static let navigatorLabelWidth: CGFloat = 160
    static let classicButtonWidth: CGFloat = 102
    static let classicButtonHeight: CGFloat = 32
    static let classicButtonInset: CGFloat = 6
    static let buttonGap: CGFloat = 8
    static let rowHeight: CGFloat = 24
    static let minimumContentSize = NSSize(width: 860, height: 560)

    struct Inputs: Equatable {
        var pathWidth: CGFloat
        var intoLabelWidth: CGFloat
        var newButtonWidth: CGFloat
        var nameLabelWidth: CGFloat
        var goBackWidth: CGFloat
    }

    struct Frames: Equatable {
        // existing-table header
        var title, path, intoLabel, target, newButton: NSRect
        // new-table header
        var nameLabel, nameField, info: NSRect
        var leftCard, leftTitle, navigatorLabel, previousRow, nextRow, table: NSRect
        var rightCard, rightTitle, options: NSRect
        var goBack, cancel, importButton: NSRect
    }

    static func frames(in b: NSRect, _ i: Inputs) -> Frames {
        let m = margin, p = cardPadding
        let headerY = b.maxY - m - headerHeight
        let title = NSRect(x: b.minX + m, y: headerY, width: 110, height: headerHeight)
        let newButton = NSRect(x: b.maxX - m - i.newButtonWidth, y: headerY + 2, width: i.newButtonWidth, height: 24)
        let target = NSRect(x: newButton.minX - 8 - targetWidth, y: headerY + 2, width: targetWidth, height: 24)
        let intoLabel = NSRect(x: target.minX - 6 - i.intoLabelWidth, y: headerY + 6, width: i.intoLabelWidth, height: 16)
        let pathX = title.maxX + 10
        let path = NSRect(x: pathX, y: headerY + 2, width: max(0, min(i.pathWidth, intoLabel.minX - 16 - pathX)), height: 24)
        let info = NSRect(x: b.maxX - m - 20, y: headerY + 4, width: 20, height: 20)
        let nameField = NSRect(x: info.minX - 8 - nameFieldWidth, y: headerY + 3, width: nameFieldWidth, height: 22)
        let nameLabel = NSRect(x: nameField.minX - 6 - i.nameLabelWidth, y: headerY + 6, width: i.nameLabelWidth, height: 16)

        let footerY = b.minY + m
        let goBack = NSRect(x: b.minX + m, y: footerY + 2, width: i.goBackWidth, height: 24)
        let importButton = NSRect(x: b.maxX - m + classicButtonInset - classicButtonWidth, y: footerY - 2,
                                  width: classicButtonWidth, height: classicButtonHeight)
        let cancel = importButton.offsetBy(dx: -(classicButtonWidth - 2 * classicButtonInset + buttonGap), dy: 0)

        let bodyY = b.minY + m + footerHeight + gap
        let bodyHeight = max(0, b.height - 2 * (m + headerHeight + gap))
        let inner = max(0, b.width - 2 * m - gap)
        let rightWidth = max(optionsMinWidth, (inner * optionsShare).rounded())
        let leftWidth = max(0, inner - rightWidth)
        let leftCard = NSRect(x: b.minX + m, y: bodyY, width: leftWidth, height: bodyHeight)
        let rightCard = NSRect(x: leftCard.maxX + gap, y: bodyY, width: rightWidth, height: bodyHeight)

        let leftTitle = NSRect(x: leftCard.minX + p, y: leftCard.maxY - p - titleHeight, width: 140, height: titleHeight)
        let nextRow = NSRect(x: leftCard.maxX - p - 20, y: leftCard.maxY - p - 18, width: 20, height: 20)
        let previousRow = nextRow.offsetBy(dx: -24, dy: 0)
        let navigatorLabel = NSRect(x: previousRow.minX - 6 - navigatorLabelWidth, y: leftCard.maxY - p - 15,
                                    width: navigatorLabelWidth, height: 14)
        let tableTop = leftTitle.minY - titleGap
        let table = NSRect(x: leftCard.minX + p, y: leftCard.minY + p, width: max(0, leftWidth - 2 * p),
                           height: max(0, tableTop - (leftCard.minY + p)))
        let rightTitle = NSRect(x: rightCard.minX + p, y: rightCard.maxY - p - titleHeight, width: max(0, rightWidth - 2 * p), height: titleHeight)
        let options = NSRect(x: rightCard.minX + p, y: rightCard.minY + p, width: max(0, rightWidth - 2 * p),
                             height: max(0, rightTitle.minY - titleGap - (rightCard.minY + p)))
        return Frames(title: title, path: path, intoLabel: intoLabel, target: target, newButton: newButton,
                      nameLabel: nameLabel, nameField: nameField, info: info,
                      leftCard: leftCard, leftTitle: leftTitle, navigatorLabel: navigatorLabel, previousRow: previousRow, nextRow: nextRow, table: table,
                      rightCard: rightCard, rightTitle: rightTitle, options: options,
                      goBack: goBack, cancel: cancel, importButton: importButton)
    }

    struct MethodSegments: Equatable {
        var enabled: [Bool]
        var selected: Int
    }

    /// `itemEnabled` in tag order INSERT, REPLACE, UPDATE.
    static func methodSegments(itemEnabled: [Bool], selectedTag: Int, newTableMode: Bool) -> MethodSegments {
        if newTableMode { return MethodSegments(enabled: [true, false, false], selected: 0) }
        let enabled = (0..<3).map { $0 < itemEnabled.count ? itemEnabled[$0] : false }
        return MethodSegments(enabled: enabled, selected: (0..<3).contains(selectedTag) ? selectedTag : 0)
    }
}
