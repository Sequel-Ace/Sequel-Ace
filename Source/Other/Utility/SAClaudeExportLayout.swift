//
//  SAClaudeExportLayout.swift
//  Sequel Ace
//
//  Frames for the Claude Export dialog: header, body cards (table list, options, save-to), footer, the option
//  rows flow, the table-list column titles and the source switcher mirror. Pure geometry, shared with Unit Tests.
//  Coordinates are AppKit's (origin bottom-left).
//

import AppKit

enum SAClaudeExportLayout {
    static let margin: CGFloat = 16
    static let gap: CGFloat = 10
    static let headerHeight: CGFloat = 28
    static let footerHeight: CGFloat = 28
    static let cardPadding: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let sectionTitleHeight: CGFloat = 16
    static let titleGap: CGFloat = 6
    static let switcherHeight: CGFloat = 26
    static let checkboxRowHeight: CGFloat = 20
    static let barHeight: CGFloat = 24
    static let rowHeight: CGFloat = 22
    static let rowGap: CGFloat = 4
    static let groupGap: CGFloat = 8
    static let indent: CGFloat = 18
    static let saveCardHeight: CGFloat = 100
    static let optionsMinWidth: CGFloat = 280
    static let optionsShare: CGFloat = 0.45
    static let checkboxColumnWidth: CGFloat = 72
    static let classicButtonWidth: CGFloat = 104
    static let classicButtonHeight: CGFloat = 32
    static let classicButtonInset: CGFloat = 6
    static let buttonGap: CGFloat = 8
    static let presetsWidth: CGFloat = 104
    static let changeWidth: CGFloat = 96
    static let changeHeight: CGFloat = 29
    static let minimumContentSize = NSSize(width: 760, height: 600)

    // MARK: Window

    struct Window: Equatable {
        var title, formatSwitcher, body, presets, info, cancel, export: NSRect
    }

    static func window(in bounds: NSRect, switcherWidth: CGFloat) -> Window {
        let m = margin, W = bounds.width, H = bounds.height
        let headerY = bounds.minY + H - m - headerHeight
        let title = NSRect(x: bounds.minX + m, y: headerY, width: 200, height: headerHeight)
        let switcher = NSRect(x: bounds.minX + W - m - switcherWidth, y: headerY + 1, width: switcherWidth, height: switcherHeight)
        let bodyY = bounds.minY + m + footerHeight + gap
        let body = NSRect(x: bounds.minX, y: bodyY, width: W, height: max(0, H - 2 * (m + footerHeight + gap)))
        let footerY = bounds.minY + m
        let presets = NSRect(x: bounds.minX + m, y: footerY + 2, width: presetsWidth, height: 24)
        let export = NSRect(x: bounds.minX + W - m + classicButtonInset - classicButtonWidth, y: footerY - 2,
                            width: classicButtonWidth, height: classicButtonHeight)
        let cancel = export.offsetBy(dx: -(classicButtonWidth - 2 * classicButtonInset + buttonGap), dy: 0)
        let infoX = presets.maxX + 12
        let info = NSRect(x: infoX, y: footerY + 7, width: max(0, cancel.minX + classicButtonInset - 12 - infoX), height: 14)
        return Window(title: title, formatSwitcher: switcher, body: body, presets: presets, info: info, cancel: cancel, export: export)
    }

    // MARK: Body

    struct BodyInputs: Equatable {
        var sourceSwitcherWidth: CGFloat, showsFilePerTable: Bool
        var allWidth: CGFloat, noneWidth: CGFloat, customiseWidth: CGFloat
        var compressionLabelWidth: CGFloat, compressionWidth: CGFloat, lowMemoryWidth: CGFloat
    }

    struct Body: Equatable {
        var leftCard, leftTitle, sourceSwitcher, filePerTable, tableList, bar, refresh, none, all: NSRect
        var rightCard, rightTitle, options: NSRect
        var saveCard, saveTitle, folderGlyph, path, change, fileGlyph, filename, customise, compressionLabel, compression, lowMemory: NSRect
    }

    static func body(in bounds: NSRect, _ i: BodyInputs) -> Body {
        let m = margin, p = cardPadding
        let saveCard = NSRect(x: bounds.minX + m, y: bounds.minY, width: max(0, bounds.width - 2 * m), height: saveCardHeight)
        let columnsY = saveCard.maxY + gap
        let columnsH = max(0, bounds.maxY - columnsY)
        let inner = max(0, bounds.width - 2 * m - gap)
        let rightW = max(optionsMinWidth, (inner * optionsShare).rounded())
        let leftW = max(0, inner - rightW)
        let leftCard = NSRect(x: bounds.minX + m, y: columnsY, width: leftW, height: columnsH)
        let rightCard = NSRect(x: leftCard.maxX + gap, y: columnsY, width: rightW, height: columnsH)

        func title(in card: NSRect) -> NSRect {
            NSRect(x: card.minX + p, y: card.maxY - p - sectionTitleHeight, width: max(0, card.width - 2 * p), height: sectionTitleHeight)
        }
        let leftTitle = title(in: leftCard)
        let contentX = leftCard.minX + p, contentW = max(0, leftW - 2 * p)
        let switcher = NSRect(x: contentX, y: leftTitle.minY - titleGap - switcherHeight,
                              width: min(i.sourceSwitcherWidth, contentW), height: switcherHeight)
        let filePerTable = i.showsFilePerTable
            ? NSRect(x: contentX, y: switcher.minY - rowGap - checkboxRowHeight, width: contentW, height: checkboxRowHeight)
            : NSRect(x: contentX, y: switcher.minY, width: contentW, height: 0)
        let bar = NSRect(x: contentX, y: leftCard.minY + 8, width: contentW, height: barHeight)
        let listTop = (i.showsFilePerTable ? filePerTable.minY : switcher.minY) - rowGap
        let tableList = NSRect(x: contentX, y: bar.maxY + rowGap, width: contentW, height: max(0, listTop - (bar.maxY + rowGap)))
        let refresh = NSRect(x: bar.minX, y: bar.minY + 2, width: 20, height: 20)
        let all = NSRect(x: bar.maxX - i.allWidth, y: bar.minY, width: i.allWidth, height: barHeight)
        let none = NSRect(x: all.minX - 4 - i.noneWidth, y: bar.minY, width: i.noneWidth, height: barHeight)

        let rightTitle = title(in: rightCard)
        let optionsY = rightCard.minY + p
        let options = NSRect(x: rightCard.minX + p, y: optionsY, width: max(0, rightW - 2 * p),
                             height: max(0, rightTitle.minY - titleGap - optionsY))

        let saveTitle = title(in: saveCard)
        let row1 = saveTitle.minY - titleGap - 24, row2 = saveCard.minY + p
        let folderGlyph = NSRect(x: saveCard.minX + p, y: row1 + 4, width: 16, height: 16)
        let change = NSRect(x: saveCard.maxX - p + classicButtonInset - changeWidth, y: row1 - 3, width: changeWidth, height: changeHeight)
        let pathX = folderGlyph.maxX + 8
        let path = NSRect(x: pathX, y: row1 + 1, width: max(0, change.minX + classicButtonInset - 8 - pathX), height: 22)
        let fileGlyph = NSRect(x: saveCard.minX + p, y: row2 + 4, width: 16, height: 16)
        let lowMemory = NSRect(x: saveCard.maxX - p - i.lowMemoryWidth, y: row2 + 2, width: i.lowMemoryWidth, height: 20)
        let compression = NSRect(x: lowMemory.minX - 16 - i.compressionWidth, y: row2, width: i.compressionWidth, height: 24)
        let compressionLabel = NSRect(x: compression.minX - 6 - i.compressionLabelWidth, y: row2 + 5, width: i.compressionLabelWidth, height: 14)
        let customise = NSRect(x: compressionLabel.minX - 16 - i.customiseWidth, y: row2, width: i.customiseWidth, height: 24)
        let filenameX = fileGlyph.maxX + 8
        let filename = NSRect(x: filenameX, y: row2 + 4, width: max(0, customise.minX - 8 - filenameX), height: 16)

        return Body(leftCard: leftCard, leftTitle: leftTitle, sourceSwitcher: switcher, filePerTable: filePerTable, tableList: tableList,
                    bar: bar, refresh: refresh, none: none, all: all, rightCard: rightCard, rightTitle: rightTitle, options: options,
                    saveCard: saveCard, saveTitle: saveTitle, folderGlyph: folderGlyph, path: path, change: change, fileGlyph: fileGlyph,
                    filename: filename, customise: customise, compressionLabel: compressionLabel, compression: compression, lowMemory: lowMemory)
    }

    // MARK: Option rows

    enum OptionRow: Equatable { case title, control(indented: Bool) }

    static func optionRows(_ rows: [OptionRow], in content: NSRect) -> [NSRect] {
        var top = content.maxY
        var result: [NSRect] = []
        for (index, row) in rows.enumerated() {
            if index > 0 { top -= rowGap + (row == .title ? groupGap : 0) }
            switch row {
            case .title:
                result.append(NSRect(x: content.minX, y: top - sectionTitleHeight, width: content.width, height: sectionTitleHeight))
                top -= sectionTitleHeight
            case .control(let indented):
                let x = content.minX + (indented ? indent : 0)
                result.append(NSRect(x: x, y: top - rowHeight, width: max(0, content.maxX - x), height: rowHeight))
                top -= rowHeight
            }
        }
        return result
    }

    // MARK: Table list column titles

    enum Format: Int { case sql = 0, csv, xml, dot }   // = SPExportType

    struct ColumnTitles: Equatable { var structure: String; var content: String; var drop: String }

    static func columnTitles(for format: Format) -> ColumnTitles {
        let structure = NSLocalizedString("ClaudeExportColumnStructure", value: "Structure", comment: "export dialog: table list column header, include structure")
        let drop = NSLocalizedString("ClaudeExportColumnDrop", value: "Drop", comment: "export dialog: table list column header, include DROP TABLE")
        let content = format == .sql
            ? NSLocalizedString("ClaudeExportColumnContent", value: "Content", comment: "export dialog: table list column header, include content")
            : NSLocalizedString("ClaudeExportColumnInclude", value: "Include", comment: "export dialog: table list column header, include the table")
        return ColumnTitles(structure: structure, content: content, drop: drop)
    }

    // MARK: Source switcher

    /// Source switcher order: Tables, Filtered results, Query results → pop-up (SPExportSource) indices.
    static let popUpIndexForSegment = [2, 0, 1]

    struct SourceSegments: Equatable { var enabled: [Bool]; var selected: Int }

    static func sourceSegments(format: Format, popUpEnabled: [Bool], popUpSelected: Int) -> SourceSegments {
        guard format != .dot, popUpEnabled.count == 3 else { return SourceSegments(enabled: [false, false, false], selected: 0) }
        let enabled = popUpIndexForSegment.map { popUpEnabled[$0] }
        let selected = popUpIndexForSegment.firstIndex(of: popUpSelected) ?? 0
        return SourceSegments(enabled: enabled, selected: selected)
    }
}
