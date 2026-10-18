//
//  SAClaudeSettingsPanes.swift
//  Sequel Ace
//
//  The Settings window's bespoke rows: the controls of the custom rows (`SAClaudeSettingCustom`), the dynamic pills
//  (favourites, encodings, SSH config, known hosts) and the plain-looking rows whose control calls pane code (the MCP
//  port), plus any row or section that needs more than a control — registered with each window's
//  SAClaudeSettingsViewRegistry (see SAClaudeSettingsWindow.swift). Until a row is registered the window shows a
//  placeholder for its control.
//
//  App target only.
//

import SwiftUI

enum SAClaudeSettingsPanes {

    /// Called once per Settings window, before its content is first drawn.
    @MainActor static func register(in registry: SAClaudeSettingsViewRegistry) {
        // Filled by the panes' rows: registry.registerControl(for: .editorFont) { context in … },
        // registry.registerControl(forDynamicSource: "favorites") { … }, registry.registerControl(forRow: "mcpPort") { … },
        // registry.registerRow("cipherOrder") { context in … }, registry.registerSection("editorGridColours") { … }.
    }
}
