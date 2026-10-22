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

    /// Verifies the chip metrics: 20pt chips with a 6pt radius in both sidebars.
    func testChipMetrics() {
        XCTAssertEqual(SAClaudeKindColours.sidebarChipSize, 20)
        XCTAssertEqual(SAClaudeKindColours.settingsChipSize, 20)
        XCTAssertEqual(SAClaudeKindColours.chipRadius, 6)
    }
}
