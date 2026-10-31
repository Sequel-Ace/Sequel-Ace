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

    func testAlertFirstButtonWithReturnIsPrimary() {
        XCTAssertEqual(style(button("OK") { $0.isAlertButton = true; $0.alertButtonIndex = 0; $0.keyEquivalent = "\r"; $0.alertHasReturnButton = true }),
                       .primaryButton)
    }

    func testAlertReturnButtonIsPrimaryWhenItIsNotTheFirst() {
        let replace = button("Replace") { $0.isAlertButton = true; $0.alertButtonIndex = 0; $0.keyEquivalent = "r"; $0.alertHasReturnButton = true }
        let cancel = button("Cancel") { $0.isAlertButton = true; $0.alertButtonIndex = 1; $0.keyEquivalent = "\r"; $0.alertHasReturnButton = true }
        XCTAssertEqual(style(replace), .secondaryButton)
        XCTAssertEqual(style(cancel), .primaryButton)
    }

    func testAlertWithoutReturnButtonMakesItsFirstButtonPrimary() {
        XCTAssertEqual(style(button("Delete") { $0.isAlertButton = true; $0.alertButtonIndex = 0; $0.keyEquivalent = "" }), .primaryButton)
        XCTAssertEqual(style(button("Keep") { $0.isAlertButton = true; $0.alertButtonIndex = 1; $0.keyEquivalent = "\u{1b}" }), .secondaryButton)
    }

    func testImageOnlyPopUpIsUnchanged() {
        var d = SAClaudeControlDescriptor(kind: .popUp)
        d.isImageOnly = true
        XCTAssertEqual(style(d), .unchanged)
    }

    func testTitledPopUpIsPill() {
        var d = SAClaudeControlDescriptor(kind: .popUp)
        d.title = "SQL"
        XCTAssertEqual(style(d), .pill)
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

    /// AppKit blanks the default button's key equivalent while its window is not key (and restores Return when it becomes
    /// key again): a walk then must still see the Return button as the primary.
    func testDefaultButtonStaysPrimaryWhileItsKeyEquivalentIsBlanked() {
        XCTAssertEqual(style(button("Save") { $0.keyEquivalent = ""; $0.isDefaultButton = true }), .primaryButton)
        XCTAssertEqual(style(button("Save") { $0.keyEquivalent = "\r"; $0.isDefaultButton = true }), .primaryButton)
        XCTAssertEqual(style(button("Cancel") { $0.keyEquivalent = "" }), .secondaryButton)
        // Still only a push-family button, and never a titleless or destructive one.
        XCTAssertEqual(style(button("Save", bezel: .recessed) { $0.isDefaultButton = true }), .unchanged)
        XCTAssertEqual(style(button("") { $0.isDefaultButton = true }), .unchanged)
        XCTAssertEqual(style(button("Delete") { $0.isDefaultButton = true; $0.isDestructive = true }), .unchanged)
    }

    func testAlertDefaultButtonStaysPrimaryWhileItsKeyEquivalentIsBlanked() {
        let second = button("Replace") { $0.isAlertButton = true; $0.alertButtonIndex = 1; $0.isDefaultButton = true; $0.alertHasReturnButton = true }
        XCTAssertEqual(style(second), .primaryButton)
        let first = button("Cancel") { $0.isAlertButton = true; $0.alertButtonIndex = 0; $0.alertHasReturnButton = true }
        XCTAssertEqual(style(first), .secondaryButton)
    }

    func testAnswersReturn() {
        XCTAssertTrue(SAClaudeSheetRules.answersReturn(button { $0.keyEquivalent = "\r" }))
        XCTAssertTrue(SAClaudeSheetRules.answersReturn(button { $0.isDefaultButton = true }))
        XCTAssertFalse(SAClaudeSheetRules.answersReturn(button { $0.keyEquivalent = "\u{1b}" }))
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

final class SAClaudeSheetButtonGeometryTests: XCTestCase {

    private func rect(_ frame: NSRect, _ size: NSControl.ControlSize = .regular, classic: Bool = true) -> NSRect {
        SAClaudeSheetButtonGeometry.buttonRect(in: frame, controlSize: size, classicMargins: classic)
    }

    func testClassicRegularFrameDraws28ptCentredInsideItsSideMargins() {
        XCTAssertEqual(rect(NSRect(x: 14, y: 13, width: 82, height: 32)), NSRect(x: 20, y: 15, width: 70, height: 28))
    }

    /// The Export sheet's "Change…" (a 29pt regular frame two points right of the path field) keeps its margins.
    func testShorterXIBFrameStillKeepsItsSideMargins() {
        XCTAssertEqual(rect(NSRect(x: 579, y: 364, width: 96, height: 29)), NSRect(x: 585, y: 364, width: 84, height: 28))
    }

    func testAlertButtonIsDrawnWhole() {
        XCTAssertEqual(rect(NSRect(x: 0, y: 0, width: 110, height: 28), classic: false), NSRect(x: 0, y: 0, width: 110, height: 28))
    }

    func testShortFrameIsDrawnAtItsOwnHeight() {
        XCTAssertEqual(rect(NSRect(x: 5, y: 5, width: 80, height: 24)), NSRect(x: 11, y: 5, width: 68, height: 24))
    }

    func testTallFrameIsCappedAndCentred() {
        XCTAssertEqual(rect(NSRect(x: 0, y: 0, width: 100, height: 37)), NSRect(x: 6, y: 4, width: 88, height: 28))
    }

    func testClassicSmallFrameDraws22ptInsideItsSideMargins() {
        XCTAssertEqual(rect(NSRect(x: 0, y: 0, width: 80, height: 28), .small), NSRect(x: 5, y: 3, width: 70, height: 22))
    }

    func testNarrowFrameNeverGoesNegative() {
        XCTAssertEqual(rect(NSRect(x: 0, y: 0, width: 8, height: 32)).width, 0)
    }
}

final class SAClaudeSheetTargetingTests: XCTestCase {

    private typealias Facts = SAClaudeSheetTargeting.Facts

    private func decide(_ mutate: (inout Facts) -> Void) -> SAClaudeSheetTargeting.Decision {
        var facts = Facts()
        mutate(&facts)
        return SAClaudeSheetTargeting.decision(for: facts)
    }

    func testAnySheetIsStyled() {
        XCTAssertEqual(decide { $0.hasSheetParent = true; $0.ownerClasses = ["SPDatabaseDocument"] }, .window)
    }

    func testAlertWindowIsStyledAsAlert() {
        XCTAssertEqual(decide { $0.isAlertWindow = true; $0.hasSheetParent = true }, .alert)
    }

    func testSavePanelOnlyGetsItsAccessoryStyled() {
        XCTAssertEqual(decide { $0.isSavePanel = true; $0.hasSheetParent = true; $0.isPlainOrAppWindowClass = false }, .accessoryOnly)
    }

    func testListedAuxiliaryWindowIsStyled() {
        XCTAssertEqual(decide { $0.ownerClasses = ["SPProcessListController"] }, .window)
        XCTAssertEqual(decide { $0.ownerClasses = ["NSObject", "SPPreferenceController"] }, .window)
    }

    func testAdvancedFilterPanelIsStyled() {
        XCTAssertEqual(decide { $0.ownerClasses = ["SPFilterTableController"] }, .window)
        XCTAssertTrue(SAClaudeSheetTargeting.auxiliaryOwnerClasses.contains("SPFilterTableController"))
    }

    func testUpdateDownloadWindowIsSkinned() {
        var facts = Facts()
        facts.ownerClasses = ["Sequel_Ace.ProgressWindowController"]
        XCTAssertEqual(SAClaudeSheetTargeting.decision(for: facts), .window)
        XCTAssertEqual(decide { $0.ownerClasses = ["NSObject", "ProgressWindowController"] }, .window)
    }

    func testUnlistedWindowIsSkipped() {
        XCTAssertEqual(decide { $0.ownerClasses = ["SAAboutWindowController"] }, .skip)
        XCTAssertEqual(decide { _ in }, .skip)
    }

    func testMainDocumentWindowAndConsoleAreSkippedEvenAsSheets() {
        XCTAssertEqual(decide { $0.ownerClasses = ["Sequel_Ace.SPWindowController"]; $0.hasSheetParent = true }, .skip)
        XCTAssertEqual(decide { $0.ownerClasses = ["SPQueryController"]; $0.hasSheetParent = true }, .skip)
    }

    func testModuleQualifiedSwiftOwnersAreMatchedUnqualified() {
        XCTAssertEqual(decide { $0.ownerClasses = ["Sequel_Ace.SAConnectionWindowController"]; $0.hasSheetParent = true }, .skip)
        XCTAssertEqual(decide { $0.ownerClasses = ["Sequel_Ace.SPWindowController"] }, .skip)
        XCTAssertEqual(decide { $0.ownerClasses = ["Sequel_Ace.SPPreferenceController"] }, .window)
        XCTAssertEqual(SAClaudeSheetTargeting.unqualified("Sequel_Ace.SPWindowController"), "SPWindowController")
        XCTAssertEqual(SAClaudeSheetTargeting.unqualified("SPUserManager"), "SPUserManager")
    }

    func testSystemPanelsAndPopoversAreSkipped() {
        XCTAssertEqual(decide { $0.isPlainOrAppWindowClass = false; $0.hasSheetParent = true }, .skip)
        XCTAssertEqual(decide { $0.isPlainOrAppWindowClass = false; $0.ownerClasses = ["SPPreferenceController"] }, .skip)
    }
}

final class SAClaudeNativeDrawingViewsTests: XCTestCase {

    func testAppKitsButtonAndPopUpDrawingViewsAreHidden() {
        for name in ["NSButtonBezelView", "NSButtonTextField", "NSButtonImageView", "NSPopUpIndicatorView",
                     "_NSCoreHostingView<AppKitButton>", "NSHostingView<Root>"] {
            XCTAssertTrue(SAClaudeNativeDrawingViews.isControlDrawingView(className: name), name)
        }
    }

    func testOtherSubviewsOfAControlStay() {
        for name in ["NSView", "NSTextField", "NSImageView", "SAClaudeBadgeView", "NSButton", ""] {
            XCTAssertFalse(SAClaudeNativeDrawingViews.isControlDrawingView(className: name), name)
        }
    }

    func testBoxDrawingViews() {
        func isDrawing(_ name: String, content: Bool = false, field: Bool = false, text: String = "", title: String = "Login Information") -> Bool {
            SAClaudeNativeDrawingViews.isBoxDrawingView(className: name, isContentView: content, isTextField: field, text: text, boxTitle: title)
        }
        // macOS 27's NSBox: its SwiftUI box view and the text field showing its title.
        XCTAssertTrue(isDrawing("_NSCoreHostingView<AppKitBoxView>"))
        XCTAssertTrue(isDrawing("NSTextField", field: true, text: "Login Information"))
        // The content view, any other text, and an untitled box's fields stay.
        XCTAssertFalse(isDrawing("NSView", content: true))
        XCTAssertFalse(isDrawing("NSTextField", content: true, field: true, text: "Login Information"))
        XCTAssertFalse(isDrawing("NSTextField", field: true, text: "Username:"))
        XCTAssertFalse(isDrawing("NSTextField", field: true, text: "", title: ""))
        XCTAssertFalse(isDrawing("NSView"))
    }
}

final class SAClaudeTitledBoxGeometryTests: XCTestCase {

    func testTitleOnTheOutlineLeavesAPaddedGap() {
        // A title straddling the card's top edge.
        let gap = SAClaudeTitledBoxGeometry.titleGap(titleRect: NSRect(x: 12, y: 92, width: 120, height: 14),
                                                     borderRect: NSRect(x: 0, y: 0, width: 300, height: 99),
                                                     titleOriginX: 12, titleWidth: 80)
        XCTAssertEqual(gap, NSRect(x: 9, y: 92, width: 86, height: 14))
    }

    func testTitleAboveTheCardLeavesNoGap() {
        // macOS 26+ lays the title out above the border: the outline is drawn whole.
        XCTAssertNil(SAClaudeTitledBoxGeometry.titleGap(titleRect: NSRect(x: 12, y: 100, width: 120, height: 14),
                                                        borderRect: NSRect(x: 0, y: 0, width: 300, height: 99),
                                                        titleOriginX: 12, titleWidth: 80))
    }

    func testTitleJustOverlappingTheCardLeavesNoGap() {
        // The title rect dips 2pt into the border rect, but the outline runs below the text: no notch in the card.
        XCTAssertNil(SAClaudeTitledBoxGeometry.titleGap(titleRect: NSRect(x: 12, y: 97, width: 120, height: 14),
                                                        borderRect: NSRect(x: 0, y: 0, width: 300, height: 99),
                                                        titleOriginX: 12, titleWidth: 80))
    }

    func testTitleOnTheBottomEdgeLeavesAGap() {
        let gap = SAClaudeTitledBoxGeometry.titleGap(titleRect: NSRect(x: 12, y: 13, width: 120, height: 14),
                                                     borderRect: NSRect(x: 0, y: 20, width: 300, height: 80),
                                                     titleOriginX: 12, titleWidth: 80)
        XCTAssertEqual(gap, NSRect(x: 9, y: 13, width: 86, height: 14))
    }

    func testEmptyTitleLeavesNoGap() {
        XCTAssertNil(SAClaudeTitledBoxGeometry.titleGap(titleRect: NSRect(x: 12, y: 92, width: 120, height: 14),
                                                        borderRect: NSRect(x: 0, y: 0, width: 300, height: 99),
                                                        titleOriginX: 12, titleWidth: 0))
    }
}

final class SAClaudeClassSwapTests: XCTestCase {

    private final class Observer: NSObject {
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                                   context: UnsafeMutableRawPointer?) {}
    }

    /// Sends its change notifications by hand, so KVO doesn't need a runtime subclass to observe it.
    private final class ManuallyNotified: NSObject {
        override class func automaticallyNotifiesObservers(forKey key: String) -> Bool { false }
        @objc var value = 0 {
            willSet { willChangeValue(forKey: "value") }
            didSet { didChangeValue(forKey: "value") }
        }
    }

    func testUnobservedButtonMayChangeClass() {
        XCTAssertTrue(SAClaudeClassSwap.mayChangeClass(of: NSButton(title: "OK", target: nil, action: nil)))
    }

    func testKVOObservedButtonMayNotChangeClassUntilTheObserverLeaves() {
        let button = NSButton(title: "OK", target: nil, action: nil)
        let observer = Observer()
        button.addObserver(observer, forKeyPath: "hidden", options: [], context: nil)
        XCTAssertFalse(SAClaudeClassSwap.mayChangeClass(of: button))
        button.removeObserver(observer, forKeyPath: "hidden")
        XCTAssertTrue(SAClaudeClassSwap.mayChangeClass(of: button))
    }

    func testManuallyNotifiedObservedObjectMayNotChangeClass() {
        let object = ManuallyNotified()
        let observer = Observer()
        object.addObserver(observer, forKeyPath: "value", options: [], context: nil)
        defer { object.removeObserver(observer, forKeyPath: "value") }
        // No KVO runtime subclass: only the observation info shows the observer.
        XCTAssertTrue(object_getClass(object) == ManuallyNotified.self)
        XCTAssertFalse(SAClaudeClassSwap.mayChangeClass(of: object))
    }

    func testStackViewArrangedButtonIsObserved() {
        let button = NSButton(title: "OK", target: nil, action: nil)
        let stack = NSStackView(views: [button])
        XCTAssertFalse(SAClaudeClassSwap.mayChangeClass(of: button))
        stack.removeArrangedSubview(button)
        button.removeFromSuperview()
    }
}

final class SAClaudeRecolouringTests: XCTestCase {

    private typealias R = SAClaudeRecolouring

    func testUnmarkedSystemLabelTakesTheTextTone() {
        XCTAssertEqual(R.labelTone(marked: nil, applied: nil, current: .labelColor, isSmall: false), .text)
        XCTAssertEqual(R.labelTone(marked: nil, applied: nil, current: nil, isSmall: false), .text)
    }

    func testUnmarkedSmallOrSecondaryLabelIsMuted() {
        XCTAssertEqual(R.labelTone(marked: nil, applied: nil, current: .controlTextColor, isSmall: true), .muted)
        XCTAssertEqual(R.labelTone(marked: nil, applied: nil, current: .secondaryLabelColor, isSmall: false), .muted)
    }

    func testUnmarkedLabelWithItsOwnColourIsLeftAlone() {
        XCTAssertNil(R.labelTone(marked: nil, applied: nil, current: .systemRed, isSmall: false))
    }

    /// A label styled under an earlier theme (marked) is recoloured while it still shows the colour it was given:
    /// it may have been off-screen (Preferences' other panes) while the theme changed several times.
    func testMarkedLabelKeepsItsToneWhileItShowsTheAppliedColour() {
        let oldTheme = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        XCTAssertEqual(R.labelTone(marked: .text, applied: oldTheme, current: oldTheme, isSmall: true), .text)
        XCTAssertEqual(R.labelTone(marked: .muted, applied: oldTheme, current: oldTheme, isSmall: false), .muted)
    }

    /// Once its code sets a colour of its own (the MCP status label going green), a marked label is left alone.
    func testMarkedLabelWithACodeChosenColourIsLeftAlone() {
        let oldTheme = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        XCTAssertNil(R.labelTone(marked: .text, applied: oldTheme, current: .systemGreen, isSmall: false))
        XCTAssertEqual(R.labelTone(marked: .muted, applied: oldTheme, current: .labelColor, isSmall: false), .text)
    }

    func testOwnershipOfTextAndBackgrounds() {
        let custom = NSColor(srgbRed: 0.5, green: 0.1, blue: 0.1, alpha: 1)
        let applied = NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        XCTAssertTrue(R.ownsText(applied: nil, current: .textColor))
        XCTAssertFalse(R.ownsText(applied: nil, current: custom))
        XCTAssertTrue(R.ownsText(applied: custom, current: custom))
        XCTAssertFalse(R.ownsText(applied: applied, current: custom))
        XCTAssertTrue(R.ownsBackground(applied: nil, current: .textBackgroundColor))
        XCTAssertFalse(R.ownsBackground(applied: nil, current: custom))
        XCTAssertTrue(R.ownsBackground(applied: custom, current: custom))
        XCTAssertFalse(R.ownsBackground(applied: applied, current: custom))
    }
}
