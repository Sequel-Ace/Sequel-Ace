//
//  SAClaudeBundleEditorLayoutTests.swift
//  Unit Tests
//
//  The Bundle Editor's two-column form and the shared footer / sidebar bar geometry (SAClaudeBundleEditorLayout.swift,
//  SAClaudeUtilityWindowLayout.swift).
//

import XCTest

final class SAClaudeBundleEditorLayoutTests: XCTestCase {

    private typealias Layout = SAClaudeBundleEditorLayout

    /// The XIB's right pane (757 × 550) with its labels measured at 11pt, regular buttons.
    private func measures(left: CGFloat = 78, right: CGFloat = 92, leftRows: Int = 5, rightRows: Int = 4) -> Layout.Measures {
        Layout.Measures(leftLabelWidth: left, rightLabelWidth: right, leftRows: leftRows, rightRows: rightRows, labelHeight: 16,
                        infoWidth: 112, cancelWidth: 96, saveWidth: 96, disableWidth: 110, buttonInset: 6)
    }

    private let pane = NSRect(x: 0, y: 0, width: 757, height: 550)
    /// The controller's minimum for the right pane (SPBundleEditorController -awakeFromNib).
    private let narrowPane = NSRect(x: 0, y: 0, width: 588, height: 420)

    // MARK: Form

    func testRowsAreLevelAcrossTheColumns() {
        let frames = Layout.frames(in: pane, measures())
        XCTAssertEqual(frames.left.count, 5)
        XCTAssertEqual(frames.right.count, 4)
        for (left, right) in zip(frames.left, frames.right) {
            XCTAssertEqual(left.control.minY, right.control.minY)
            XCTAssertEqual(left.label.midY, right.label.midY, accuracy: 0.5)
        }
    }

    func testColumnsAreEqualAndApartByTheGap() {
        let frames = Layout.frames(in: pane, measures())
        let leftColumn = frames.left[0].label.minX...frames.left[0].control.maxX
        let rightColumn = frames.right[0].label.minX...frames.right[0].control.maxX
        XCTAssertEqual(leftColumn.lowerBound, Layout.margin)
        XCTAssertEqual(rightColumn.upperBound, pane.maxX - Layout.margin, accuracy: 1)
        XCTAssertEqual(rightColumn.lowerBound - leftColumn.upperBound, Layout.columnGap)
        XCTAssertEqual(leftColumn.upperBound - leftColumn.lowerBound, rightColumn.upperBound - rightColumn.lowerBound)
    }

    func testControlsInAColumnShareOneLeftEdgeAndWidth() {
        let frames = Layout.frames(in: pane, measures())
        for column in [frames.left, frames.right] {
            XCTAssertEqual(Set(column.map(\.control.minX)).count, 1)
            XCTAssertEqual(Set(column.map(\.control.width)).count, 1)
            XCTAssertEqual(Set(column.map(\.label.maxX)).count, 1)
            XCTAssertTrue(column.allSatisfy { $0.label.maxX + Layout.labelGap == $0.control.minX })
        }
    }

    func testEachColumnsLabelsGetItsWidestLabel() {
        let frames = Layout.frames(in: pane, measures(left: 78, right: 92))
        XCTAssertEqual(frames.left[0].label.width, 78)
        XCTAssertEqual(frames.right[0].label.width, 92)
    }

    func testRowsStepDownByHeightAndGap() {
        let frames = Layout.frames(in: pane, measures())
        let ys = frames.left.map(\.control.minY)
        for (upper, lower) in zip(ys, ys.dropFirst()) {
            XCTAssertEqual(upper - lower, Layout.rowHeight + Layout.rowGap)
        }
        XCTAssertTrue(frames.left.allSatisfy { $0.control.height == Layout.rowHeight })
    }

    func testALongLabelIsCappedAndLeavesTheControlHalfTheColumn() {
        let frames = Layout.frames(in: narrowPane, measures(left: 400, right: 400))
        let column = Layout.columnWidth(paneWidth: narrowPane.width)
        XCTAssertEqual(frames.left[0].label.width, min(Layout.labelMaxWidth, (column / 2).rounded(.down)))
        XCTAssertGreaterThanOrEqual(frames.left[0].control.width, column / 2 - Layout.labelGap)
    }

    func testTheNarrowestPaneStillFitsBothColumns() {
        let frames = Layout.frames(in: narrowPane, measures())
        XCTAssertLessThanOrEqual(frames.right[0].control.maxX, narrowPane.maxX - Layout.margin + 1)
        XCTAssertGreaterThan(frames.left[0].control.width, 120)
        XCTAssertGreaterThan(frames.right[0].control.width, 120)
    }

    // MARK: Header, command, footer

    func testHeaderSitsAboveTheFormWithBundleInfoOnTheMargin() {
        let frames = Layout.frames(in: pane, measures())
        XCTAssertEqual(frames.info.maxX - 6, pane.maxX - Layout.margin)
        XCTAssertEqual(frames.info.maxY, pane.maxY - Layout.top)
        XCTAssertLessThanOrEqual(frames.summary.maxX, frames.info.minX + 6 - Layout.itemGap)
        XCTAssertEqual(frames.summary.minX, Layout.margin)
        XCTAssertGreaterThan(frames.info.minY, frames.left[0].control.maxY)
    }

    func testCommandFillsBetweenTheFormAndTheFooter() {
        let frames = Layout.frames(in: pane, measures())
        let formBottom = frames.left.last!.control.minY
        XCTAssertEqual(frames.commandLabel.maxY, formBottom - Layout.formCommandGap)
        XCTAssertEqual(frames.command.maxY, frames.commandLabel.minY - Layout.commandLabelGap)
        XCTAssertEqual(frames.command.minY, frames.save.maxY + Layout.commandFooterGap)
        XCTAssertEqual(frames.command.minX, Layout.margin)
        XCTAssertEqual(frames.command.maxX, pane.maxX - Layout.margin)
        XCTAssertGreaterThan(frames.command.height, 200)
    }

    func testFooterOrderDisableHelpCancelSave() {
        let frames = Layout.frames(in: pane, measures())
        XCTAssertEqual(frames.save.maxX - 6, pane.maxX - Layout.margin)
        XCTAssertEqual((frames.save.minX + 6) - (frames.cancel.maxX - 6), SAClaudeFooterLayout.gap)
        XCTAssertEqual((frames.cancel.minX + 6) - frames.help.maxX, Layout.itemGap)
        XCTAssertLessThanOrEqual(frames.disable.maxX, frames.help.minX - Layout.itemGap)
        XCTAssertEqual(frames.disable.minX, Layout.margin)
        XCTAssertEqual(frames.help.midY, frames.save.midY, accuracy: 0.5)
        XCTAssertEqual(frames.disable.midY, frames.save.midY, accuracy: 0.5)
    }

    func testNothingOverlaps() {
        let frames = Layout.frames(in: pane, measures())
        var rects = [frames.summary, frames.info, frames.commandLabel, frames.command, frames.disable, frames.help, frames.cancel, frames.save]
        rects += (frames.left + frames.right).flatMap { [$0.label, $0.control] }
        for (i, a) in rects.enumerated() {
            XCTAssertTrue(pane.contains(a), "\(a) outside the pane")
            for b in rects[(i + 1)...] {
                XCTAssertFalse(a.intersects(b), "\(a) overlaps \(b)")
            }
        }
    }

    func testAShortPaneKeepsTheCommandAtZeroHeightNotNegative() {
        let frames = Layout.frames(in: NSRect(x: 0, y: 0, width: 600, height: 200), measures())
        XCTAssertEqual(frames.command.height, 0)
    }

    // MARK: Shared footer and bar

    func testFooterButtonsRightToLeftOnTheMargin() {
        let frames = SAClaudeFooterLayout.trailing(widths: [100, 90, 80], maxX: 400, y: 12, buttonInset: 6)
        XCTAssertEqual(frames.map(\.width), [100, 90, 80])
        XCTAssertEqual(frames[0].maxX - 6, 400 - SAClaudeFooterLayout.margin)
        XCTAssertEqual((frames[0].minX + 6) - (frames[1].maxX - 6), SAClaudeFooterLayout.gap)
        XCTAssertEqual((frames[1].minX + 6) - (frames[2].maxX - 6), SAClaudeFooterLayout.gap)
        XCTAssertTrue(frames.allSatisfy { $0.minY == 12 && $0.height == SAClaudeFooterLayout.height })
        XCTAssertEqual(SAClaudeFooterLayout.leadingEdge(of: frames, buttonInset: 6), frames[2].minX + 6)
    }

    func testSidebarBarButtons() {
        let frames = SAClaudeSidebarBarLayout.buttons(count: 3, x: 6, midY: 16)
        XCTAssertEqual(frames.map(\.minX), [6, 36, 66])
        XCTAssertTrue(frames.allSatisfy { $0.midY == 16 && $0.width == 28 && $0.height == 28 })
        XCTAssertTrue(SAClaudeSidebarBarLayout.buttons(count: 0, x: 6, midY: 16).isEmpty)
    }
}
