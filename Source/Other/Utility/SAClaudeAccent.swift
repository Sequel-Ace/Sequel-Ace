//
//  SAClaudeAccent.swift
//  Sequel Ace
//
//  The accent colour of the Claude look: the user's choice (UserDefaults
//  "ClaudeAccentColour", an archived sRGB NSColor) or clay when absent. The
//  decorative clay statics read it; error colours stay fixed clay
//  (`SAClaudeStatusChrome.errorClay`). Shared with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeAccent: NSObject {

    static let defaultsKey = "ClaudeAccentColour"
    /// Clay `#D97757`.
    static let clayAccent = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    /// Clay `#C6613F`, the deeper clay used for fills.
    static let clayFill = NSColor(srgbRed: 0xC6 / 255, green: 0x61 / 255, blue: 0x3F / 255, alpha: 1)
    /// Posted (on the calling thread) whenever `store` writes or resets the accent.
    static let didChangeNotification = Notification.Name("SAClaudeAccentDidChange")

    private static let pressedRatio: CGFloat = 0.12
    private static let onAccentLuminanceLimit: CGFloat = 0.6
    private static let nearBlack = NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255, alpha: 1)

    // MARK: - Storage

    /// The stored colour (sRGB) or nil.
    static func stored(in defaults: UserDefaults = .standard) -> NSColor? {
        guard let colour = SAArchiving.color(from: defaults.data(forKey: defaultsKey)) else { return nil }
        return colour.usingColorSpace(.sRGB)
    }

    /// Stores `colour` as an archived sRGB colour; nil resets to clay. Posts `didChangeNotification`.
    static func store(_ colour: NSColor?, in defaults: UserDefaults = .standard) {
        if let colour, let srgb = colour.usingColorSpace(.sRGB), let data = SAArchiving.archivedData(forColor: srgb) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    // MARK: - Resolved colours

    @objc static var accent: NSColor { accent(in: .standard) }
    @objc static var fill: NSColor { fill(in: .standard) }
    @objc static var onAccent: NSColor { onAccent(in: .standard) }

    static func accent(in defaults: UserDefaults) -> NSColor { stored(in: defaults) ?? clayAccent }
    static func fill(in defaults: UserDefaults) -> NSColor { stored(in: defaults) ?? clayFill }

    /// The fill mixed 12% towards white on a dark theme, towards black on a light one.
    static func fillPressed(darkTheme: Bool, in defaults: UserDefaults = .standard) -> NSColor {
        let target = darkTheme ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        return SAClaudeEditorChrome.derivedColour(text: target, background: fill(in: defaults), ratio: pressedRatio)
    }

    /// The text colour on the fill: white, or near-black `#1A1A1A` when the fill is light.
    static func onAccent(in defaults: UserDefaults) -> NSColor {
        relativeLuminance(fill(in: defaults)) > onAccentLuminanceLimit ? nearBlack : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    /// WCAG relative luminance of the colour's sRGB value.
    static func relativeLuminance(_ colour: NSColor) -> CGFloat {
        guard let c = colour.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }
}
