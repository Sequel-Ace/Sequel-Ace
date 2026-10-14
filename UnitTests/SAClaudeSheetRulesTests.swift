//
//  SAClaudeSheetRulesTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeSheetRulesTests: XCTestCase {

    private func style(_ d: SAClaudeControlDescriptor) -> SAClaudeControlStyle { SAClaudeSheetRules.style(for: d) }

    private func button(_ title: String = "Save", type: NSButton.ButtonType = .momentaryPushIn,
                        bezel: NSButton.BezelStyle = .push, mutate: (inout SAClaudeControlDescriptor) -> Void = { _ in }) -> SAClaudeControlDescriptor {
        var d = SAClaudeControlDescriptor(kind: .button)
        d.buttonType = type
        d.bezelStyle = bezel
        d.title = title
        mutate(&d)
        return d
    }

    // MARK: Buttons

    func testSwitchButtonIsCheckbox() {
        XCTAssertEqual(style(button("Remember", type: .switch, bezel: .regularSquare)), .checkbox)
    }

    func testRadioButtonIsRadio() {
        XCTAssertEqual(style(button("All rows", type: .radio, bezel: .regularSquare)), .radio)
    }

    func testAlertFirstButtonIsPrimary() {
        XCTAssertEqual(style(button("OK") { $0.isAlertButton = true; $0.alertButtonIndex = 0 }), .primaryButton)
    }

    func testAlertSecondButtonIsSecondary() {
        XCTAssertEqual(style(button("Cancel") { $0.isAlertButton = true; $0.alertButtonIndex = 1 }), .secondaryButton)
    }

    func testReturnKeyEquivalentIsPrimary() {
        XCTAssertEqual(style(button("Connect") { $0.keyEquivalent = "\r" }), .primaryButton)
    }

    func testReturnWithNonPushBezelIsUnchanged() {
        let bezels: [NSButton.BezelStyle] = [.helpButton, .recessed, .smallSquare, .texturedRounded, .inline, .circular]
        for bezel in bezels {
            XCTAssertEqual(style(button("Go", bezel: bezel) { $0.keyEquivalent = "\r" }), .unchanged, "bezel \(bezel.rawValue)")
        }
    }

    func testReturnWithoutBezelIsUnchanged() {
        var d = SAClaudeControlDescriptor(kind: .button)
        d.title = "Go"
        d.keyEquivalent = "\r"
        XCTAssertEqual(style(d), .unchanged)
    }

    func testReturnWithFlexiblePushIsPrimary() {
        XCTAssertEqual(style(button("Go", bezel: .flexiblePush) { $0.keyEquivalent = "\r" }), .primaryButton)
        XCTAssertEqual(style(button("Go", bezel: .regularSquare) { $0.keyEquivalent = "\r" }), .primaryButton)
    }

    func testAlertFirstButtonIsPrimaryWithAnyBezel() {
        XCTAssertEqual(style(button("OK", bezel: .smallSquare) { $0.isAlertButton = true; $0.alertButtonIndex = 0 }), .primaryButton)
    }

    func testAlertIndexZeroWithoutAlertFlagIsNotPrimary() {
        XCTAssertEqual(style(button("OK") { $0.alertButtonIndex = 0 }), .secondaryButton)
        XCTAssertEqual(style(button("OK", bezel: .smallSquare) { $0.alertButtonIndex = 0 }), .unchanged)
    }

    func testTitlelessCheckboxAndRadioKeepTheirStyle() {
        XCTAssertEqual(style(button("", type: .switch, bezel: .regularSquare)), .checkbox)
        XCTAssertEqual(style(button("", type: .radio, bezel: .regularSquare)), .radio)
    }

    func testPlainPushButtonIsSecondary() {
        XCTAssertEqual(style(button("Browse…")), .secondaryButton)
    }

    func testBothSpellingsOfPushBezelsAreSecondary() {
        XCTAssertEqual(style(button(bezel: .push)), .secondaryButton)
        XCTAssertEqual(style(button(bezel: .flexiblePush)), .secondaryButton)
        XCTAssertEqual(style(button(bezel: .rounded)), .secondaryButton)
        XCTAssertEqual(style(button(bezel: .regularSquare)), .secondaryButton)
    }

    func testOtherBezelsAreUnchanged() {
        let others: [NSButton.BezelStyle] = [.helpButton, .disclosure, .recessed, .inline, .smallSquare, .texturedRounded, .circular]
        for bezel in others {
            XCTAssertEqual(style(button("Title", bezel: bezel)), .unchanged, "bezel \(bezel.rawValue)")
        }
    }

    func testMissingBezelIsUnchanged() {
        var d = SAClaudeControlDescriptor(kind: .button)
        d.title = "Title"
        XCTAssertEqual(style(d), .unchanged)
    }

    func testImageOnlyPushButtonIsUnchanged() {
        XCTAssertEqual(style(button("")), .unchanged)
    }

    func testTitlelessAlertFirstButtonIsUnchanged() {
        XCTAssertEqual(style(button("") { $0.isAlertButton = true; $0.alertButtonIndex = 0 }), .unchanged)
    }

    func testDestructiveButtonIsUnchanged() {
        XCTAssertEqual(style(button("Delete") { $0.isAlertButton = true; $0.alertButtonIndex = 0; $0.isDestructive = true }), .unchanged)
        XCTAssertEqual(style(button("Delete") { $0.isDestructive = true }), .unchanged)
    }

    func testHelpButtonIsUnchanged() {
        XCTAssertEqual(style(button("", bezel: .helpButton)), .unchanged)
        XCTAssertEqual(style(button("Help", bezel: .helpButton)), .unchanged)
    }

    // MARK: Text fields

    private func field(editable: Bool, bezeled: Bool, size: CGFloat = 13) -> SAClaudeControlDescriptor {
        var d = SAClaudeControlDescriptor(kind: .textField)
        d.isEditable = editable
        d.isBezeledOrBordered = bezeled
        d.fontSize = size
        return d
    }

    func testEditableBezeledFieldIsField() {
        XCTAssertEqual(style(field(editable: true, bezeled: true)), .field)
    }

    func testEditableUnbezeledUnborderedFieldIsUnchanged() {
        XCTAssertEqual(style(field(editable: true, bezeled: false)), .unchanged)
    }

    func testStaticLabelSizes() {
        XCTAssertEqual(style(field(editable: false, bezeled: false, size: 13)), .label)
        XCTAssertEqual(style(field(editable: false, bezeled: false, size: 12)), .label)
        XCTAssertEqual(style(field(editable: false, bezeled: false, size: 11)), .mutedLabel)
        XCTAssertEqual(style(field(editable: false, bezeled: false, size: 10)), .mutedLabel)
    }

    // MARK: The rest

    func testPopUpIsPill() {
        XCTAssertEqual(style(SAClaudeControlDescriptor(kind: .popUp)), .pill)
    }

    func testBoxes() {
        var separator = SAClaudeControlDescriptor(kind: .box)
        separator.isSeparatorBox = true
        separator.boxTitle = "Ignored"
        XCTAssertEqual(style(separator), .separator)

        var titled = SAClaudeControlDescriptor(kind: .box)
        titled.boxTitle = "Options"
        XCTAssertEqual(style(titled), .titledBox)

        XCTAssertEqual(style(SAClaudeControlDescriptor(kind: .box)), .unchanged)
    }

    func testTableAndTextView() {
        XCTAssertEqual(style(SAClaudeControlDescriptor(kind: .table)), .quietTable)
        XCTAssertEqual(style(SAClaudeControlDescriptor(kind: .textView)), .editorTextView)
    }

    func testOtherKindIsUnchanged() {
        XCTAssertEqual(style(SAClaudeControlDescriptor(kind: .other)), .unchanged)
    }
}
