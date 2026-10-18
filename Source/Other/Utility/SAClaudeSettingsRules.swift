//
//  SAClaudeSettingsRules.swift
//  Sequel Ace
//
//  The decisions the Settings window's bespoke rows make, as pure functions
//  (the views in SAClaudeSettingsPanes.swift only draw what these return):
//  the favourite pill's menu and the two keys it writes, a tag pill's
//  selection (the encodings), the updates switch in App Store builds, the
//  auto-complete delay warning and the font rows' label.
//
//  Pure Swift (app + Unit Tests targets).
//

import Foundation

enum SAClaudeSettingsRules {

    // MARK: Favourite to select

    /// A node of the favourites tree (SPFavoritesController's root's children).
    indirect enum FavouriteNode: Equatable {
        case group(name: String, children: [FavouriteNode])
        case favourite(name: String, id: Int)
    }

    enum FavouriteItemKind: Equatable {
        /// "Last used": writes SelectLastFavoriteUsed = YES.
        case lastUsed
        case separator
        /// A group heading (disabled) or the "no favourites" line (disabled).
        case heading
        case favourite(id: Int)
    }

    struct FavouriteItem: Equatable {
        let title: String
        let indentation: Int
        let kind: FavouriteItemKind

        var isEnabled: Bool {
            switch kind {
            case .lastUsed, .favourite: return true
            case .separator, .heading: return false
            }
        }
    }

    /// The menu SPGeneralPreferencePane `-updateDefaultFavoritePopup` builds (SPGeneralPreferencePane.m:135-164):
    /// "Last used", a separator, then the tree — a group is a disabled heading at its depth with its children one level
    /// deeper (`-_constructMenuItemsForNode:atLevel:`, :178-219) — or one disabled "no favourites" line.
    static func favouriteMenu(_ nodes: [FavouriteNode], lastUsedTitle: String, noneTitle: String) -> [FavouriteItem] {
        var items = [FavouriteItem(title: lastUsedTitle, indentation: 0, kind: .lastUsed),
                     FavouriteItem(title: "", indentation: 0, kind: .separator)]
        guard !nodes.isEmpty else {
            return items + [FavouriteItem(title: noneTitle, indentation: 0, kind: .heading)]
        }
        func add(_ node: FavouriteNode, level: Int) {
            switch node {
            case let .group(name, children):
                items.append(FavouriteItem(title: name, indentation: level, kind: .heading))
                children.forEach { add($0, level: level + 1) }
            case let .favourite(name, id):
                items.append(FavouriteItem(title: name, indentation: level, kind: .favourite(id: id)))
            }
        }
        nodes.forEach { add($0, level: 0) }
        return items
    }

    /// The item the pill shows: "Last used" when that is chosen, else the favourite whose id is stored. A stored id no
    /// favourite has (it was deleted) shows "Last used", as `selectItemWithTag:` left the rebuilt pop-up on its first item.
    static func favouriteSelectedIndex(_ items: [FavouriteItem], selectLastUsed: Bool, defaultFavorite: Int) -> Int {
        guard !selectLastUsed else { return 0 }
        return items.firstIndex { $0.kind == .favourite(id: defaultFavorite) } ?? 0
    }

    /// What choosing item `index` writes, as `-updateDefaultFavorite:` (SPGeneralPreferencePane.m:70-83):
    /// SelectLastFavoriteUsed = (it is "Last used"), DefaultFavorite = its tag (0 for "Last used"). Nil for a heading or
    /// separator.
    static func favouriteChoice(_ items: [FavouriteItem], at index: Int) -> (selectLastUsed: Bool, defaultFavorite: Int)? {
        guard items.indices.contains(index) else { return nil }
        switch items[index].kind {
        case .lastUsed: return (true, 0)
        case .favourite(let id): return (false, id)
        case .separator, .heading: return nil
        }
    }

    // MARK: Tag pills (character set)

    /// The first item whose tag is `stored` (separators have no tag), as a `selectedTag` binding picked it; nil when
    /// none has it.
    static func selectedIndex(tags: [Int?], stored: Int) -> Int? {
        tags.firstIndex { $0 == stored }
    }

    // MARK: Updates

    struct UpdatesSwitch: Equatable {
        let isEnabled: Bool
        let isOn: Bool
        /// Show "Only available for GitHub downloads" under the row.
        let showsNote: Bool
    }

    /// App Store builds never check GitHub (SAGitHubReleaseCheckPolicy): the switch is disabled and shown off, the key
    /// left as it is, with the note — as SPNotificationsPreferencePane -preferencePaneView did (:50-61).
    static func updatesSwitch(isAppStore: Bool, stored: Bool) -> UpdatesSwitch {
        isAppStore ? UpdatesSwitch(isEnabled: false, isOn: false, showsNote: true)
                   : UpdatesSwitch(isEnabled: true, isOn: stored, showsNote: false)
    }

    // MARK: Auto-complete delay

    /// Below 0.1 s (the field allows 0) the old stepper warned (SPEditorPreferencePane -delayStepperChanged:, :380-394).
    static func showsAutoCompleteDelayWarning(_ delay: Double) -> Bool {
        delay < 0.1
    }

    // MARK: Editor and grid colours

    /// The colour rows shown: while the colours match the appearance only the mode row ("editorColours"); while Custom
    /// all of them — Start from a theme and the 11 colours were the old section's Customise-only part.
    static func colourSectionRowIDs(_ rowIDs: [String], followsAppearance: Bool) -> [String] {
        followsAppearance ? rowIDs.filter { $0 == "editorColours" } : rowIDs
    }

    // MARK: Fonts

    /// The name a font row shows: the font's display name, except for the system fonts, whose PostScript names are
    /// hidden (".AppleSystemUIFontMonospaced", display name ".SF NS Mono Light Regular"): those are SF Mono or SF Pro.
    static func fontName(postScriptName: String, displayName: String?, isFixedPitch: Bool) -> String {
        guard !postScriptName.hasPrefix(".") else { return isFixedPitch ? "SF Mono" : "SF Pro" }
        return displayName ?? postScriptName
    }

    /// A font row's label: the font's name and its size ("SF Mono 13", "Helvetica 12.5").
    static func fontLabel(name: String, pointSize: Double) -> String {
        let rounded = (pointSize * 10).rounded() / 10
        let size = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(name) \(size)"
    }
}
