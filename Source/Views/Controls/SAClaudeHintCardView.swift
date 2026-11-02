//
//  SAClaudeHintCardView.swift
//  Sequel Ace
//
//  The card behind a hint (tooltip, Type Info, help viewer): a rounded, hairline-bordered surface in
//  the palette's colours that clips its content to the corners and never takes the mouse. App target only.
//

import AppKit

final class SAClaudeHintCardView: NSView {

    init(palette: SAClaudeHintCardPalette) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = SAClaudeHintCard.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = SAClaudeHintCard.borderWidth
        layer?.masksToBounds = true
        apply(palette)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ palette: SAClaudeHintCardPalette) {
        layer?.backgroundColor = palette.surface.cgColor
        layer?.borderColor = palette.hairline.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Current palette

extension SAClaudeHintCardPalette {

    /// The card for Sequel Ace's present look: the editor theme as resolved in the app's appearance,
    /// links in the accent (its fill on a light card, as the database tint), made readable on the card's surface
    /// (`make`); the help viewer's selected tab uses this same colour.
    static func current() -> SAClaudeHintCardPalette {
        var palette: SAClaudeHintCardPalette?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            // Dynamic system colours (the theme's fallbacks) are fixed here, in this appearance.
            func resolved(_ colour: NSColor) -> NSColor { NSColor(cgColor: colour.cgColor) ?? colour }
            let stored = SAClaudeThemeColours.from(defaults: .standard)
            let theme = SAClaudeThemeColours(background: resolved(stored.background), text: resolved(stored.text),
                                             keyword: resolved(stored.keyword), variable: resolved(stored.variable),
                                             caret: resolved(stored.caret), quote: resolved(stored.quote),
                                             backtick: resolved(stored.backtick), selection: resolved(stored.selection))
            let isDark = SAClaudeGridChrome.isDark(theme.background)
            palette = make(theme: theme, accent: resolved(isDark ? SAClaudeAccent.accent : SAClaudeAccent.fill))
        }
        return palette!
    }

    static func currentPaper() -> SAClaudeHintCardPalette { paper(accent: SAClaudeAccent.fill) }
}

// MARK: - Objective-C hook

/// What the ObjC web-content code (SPTooltip, the help viewer) asks for.
@objc(SAClaudeHintCardStyler) final class SAClaudeHintCardStyler: NSObject {

    /// The `<style>` body for a hint page: the card's variables and the paper override for printing.
    @objc static func currentPageStyle() -> String {
        SAClaudeHintCardCSS.pageStyle(theme: .current(), paper: .currentPaper())
    }

    @objc static func currentIsDark() -> Bool { SAClaudeHintCardPalette.current().isDark }
}
