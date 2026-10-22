//
//  SAClaudeKindColoursTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeKindColoursTests: XCTestCase {

    /// Verifies each tables-list type gets its kind's colour, and a header row none.
    func testTableTypes() {
        let expected: [(Int, SAVividColour?)] = [
            (-1, nil), (0, .sky), (1, .violet), (2, .amber), (3, .emerald), (4, .orange), (5, .sky),
        ]
        for (type, colour) in expected {
            XCTAssertEqual(SAClaudeKindColours.colour(forTableType: type), colour, "table type \(type)")
        }
    }

    /// Verifies the nine Settings panes' chip colours, each pane a different one.
    func testSettingsPanes() {
        let expected: [SAClaudeSettingsPaneID: SAVividColour] = [
            .appearance: .pink, .startup: .sky, .tablesData: .emerald, .queryEditor: .violet, .safety: .rose,
            .queryConsole: .teal, .sshSecurity: .amber, .mcp: .blue, .updatesPrivacy: .slate,
        ]
        XCTAssertEqual(Set(expected.keys), Set(SAClaudeSettingsPaneID.allCases), "every pane is mapped")
        for (pane, colour) in expected {
            XCTAssertEqual(SAClaudeKindColours.colour(for: pane), colour, "pane \(pane.rawValue)")
        }
        let colours = SAClaudeSettingsPaneID.allCases.map { SAClaudeKindColours.colour(for: $0) }
        XCTAssertEqual(Set(colours).count, colours.count, "every pane gets a different colour")
    }

    /// Verifies the Process List groups' colours: Rose, Amber, Slate.
    func testProcessGroups() {
        XCTAssertEqual(SAClaudeKindColours.colour(for: SAClaudeProcessGroup.needsAttention), .rose)
        XCTAssertEqual(SAClaudeKindColours.colour(for: SAClaudeProcessGroup.running), .amber)
        XCTAssertEqual(SAClaudeKindColours.colour(for: SAClaudeProcessGroup.idle), .slate)
    }

    /// Verifies the Process List tones are the group's vivid ink and tint in both lightnesses, not the alert colours
    /// (which stay for the Kill buttons).
    func testProcessListTonesAreTheGroupInkAndTint() {
        for group in [SAClaudeProcessGroup.needsAttention, .running, .idle] {
            let colour = SAClaudeKindColours.colour(for: group)
            for dark in [false, true] {
                XCTAssertEqual(SAClaudeProcessListTones.colour(for: group, dark: dark), colour.ink(dark: dark), "\(group) dark \(dark) ink")
                XCTAssertEqual(SAClaudeProcessListTones.tint(for: group, dark: dark), colour.tint(dark: dark), "\(group) dark \(dark) tint")
            }
        }
        XCTAssertNotEqual(SAClaudeProcessListTones.colour(for: .needsAttention, dark: true), SAClaudeProcessListTones.red(dark: true))
        XCTAssertEqual(SAClaudeProcessListTones.red(dark: true), SAClaudeAlertChrome.redGlyphDark, "Kill buttons keep the alert red")
        XCTAssertEqual(SAClaudeProcessListTones.red(dark: false), SAClaudeAlertChrome.red)
    }

    /// Verifies a status chip's count is in the group's ink while it counts something and muted (nil) at 0.
    func testZeroCountIsMuted() {
        for group in [SAClaudeProcessGroup.needsAttention, .running, .idle] {
            for dark in [false, true] {
                XCTAssertNil(SAClaudeProcessListTones.countColour(for: group, count: 0, dark: dark), "\(group) 0")
                XCTAssertEqual(SAClaudeProcessListTones.countColour(for: group, count: 3, dark: dark),
                               SAClaudeKindColours.colour(for: group).ink(dark: dark), "\(group) 3")
            }
        }
    }

    /// Verifies a needs-attention row's text reads (≥ 4.5:1) on the Claude themes' row selection: the light ink is kept
    /// on Claude Light's, the dark ink lightened just enough on Claude Dark's (4.4:1 as is), and stays Rose-ish.
    func testAttentionTextReadsOnTheSelection() {
        let lightSelection = SAClaudeStyle.srgb(0xE3E3DE), darkSelection = SAClaudeStyle.srgb(0x383735)
        XCTAssertEqual(SAClaudeProcessListTones.attentionText(dark: false, selection: lightSelection), SAVividColour.rose.ink(dark: false))
        XCTAssertLessThan(SAClaudeHintCardPalette.contrast(SAVividColour.rose.ink(dark: true), darkSelection), 4.5)
        let lifted = SAClaudeProcessListTones.attentionText(dark: true, selection: darkSelection).usingColorSpace(.sRGB)!
        XCTAssertGreaterThanOrEqual(SAClaudeHintCardPalette.contrast(lifted, darkSelection), 4.5)
        XCTAssertGreaterThan(lifted.redComponent, lifted.greenComponent + 0.2, "still a rose")
        XCTAssertGreaterThanOrEqual(SAClaudeHintCardPalette.contrast(lifted, SAClaudeStyle.srgb(0x151515)), 4.5, "and on the list background")
    }

    /// Verifies the chip metrics: 20pt chips with a 6pt radius in both sidebars.
    func testChipMetrics() {
        XCTAssertEqual(SAClaudeKindColours.sidebarChipSize, 20)
        XCTAssertEqual(SAClaudeKindColours.settingsChipSize, 20)
        XCTAssertEqual(SAClaudeKindColours.chipRadius, 6)
    }
}
