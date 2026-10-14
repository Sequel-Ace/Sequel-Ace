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
    /// Near-black `#1A1A1A`, the title colour on a light fill.
    static let nearBlack = NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255, alpha: 1)
    private static let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// White keeps the title unless near-black has at least this much more contrast: clay `#C6613F` has
    /// 4.06:1 against white and 4.29:1 against near-black, and stays white-on-clay as it always was.
    private static let whitePreference: CGFloat = 1.25

    // MARK: - Storage

    /// The stored colour (sRGB) or nil. Reads `defaults` and unarchives every time; `accent`, `fill` and
    /// `onAccent` read `.standard` through a cache instead.
    static func stored(in defaults: UserDefaults) -> NSColor? {
        guard let colour = SAArchiving.color(from: defaults.data(forKey: defaultsKey)) else { return nil }
        return colour.usingColorSpace(.sRGB)
    }

    /// The `.standard` stored colour, unarchived once and kept until `store` or a change of the key's data.
    static func stored() -> NSColor? {
        _ = defaultsObserver
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache { return cache.colour }
        let data = UserDefaults.standard.data(forKey: defaultsKey)
        let colour = SAArchiving.color(from: data)?.usingColorSpace(.sRGB)
        cache = (data, colour)
        return colour
    }

    private static let cacheLock = NSLock()
    private static var cache: (data: Data?, colour: NSColor?)?

    /// Drops the cached colour; the next read unarchives again.
    static func invalidateCache() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
    }

    /// Drops the cache when the key's data differs from what the cache was built from (an outside write,
    /// `defaults delete`, a reset); every defaults write in the app posts this, so it compares first.
    private static let defaultsObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
        let data = UserDefaults.standard.data(forKey: defaultsKey)
        cacheLock.lock()
        if let cache, cache.data != data { SAClaudeAccent.cache = nil }
        cacheLock.unlock()
    }

    /// Stores `colour` as an archived sRGB colour; nil resets to clay. Posts `didChangeNotification`.
    static func store(_ colour: NSColor?, in defaults: UserDefaults = .standard) {
        if let colour, let srgb = colour.usingColorSpace(.sRGB), let data = SAArchiving.archivedData(forColor: srgb) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
        invalidateCache()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Marks `view` and every subview for redisplay: cells and views that draw in the accent read it at draw time.
    static func redisplay(_ view: NSView) {
        view.needsDisplay = true
        view.subviews.forEach(redisplay)
    }

    // MARK: - Resolved colours

    @objc static var accent: NSColor { stored() ?? clayAccent }
    @objc static var fill: NSColor { stored() ?? clayFill }
    @objc static var onAccent: NSColor { onAccent(fill: fill) }

    /// Calls `handler` with `owner` (on the main thread) whenever the accent changes, for as long as `owner`
    /// lives: stylers refresh whatever they cache from the accent. The observer has no queue (a writer on
    /// another thread must not wait for main) and hops to main itself.
    static func observe<Owner: AnyObject>(_ owner: Owner, _ handler: @escaping (Owner) -> Void) {
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: didChangeNotification, object: nil, queue: nil) { [weak owner] _ in
            let run = {
                guard let owner else {
                    if let token { NotificationCenter.default.removeObserver(token) }
                    return
                }
                handler(owner)
            }
            if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
        }
    }

    static func accent(in defaults: UserDefaults) -> NSColor { stored(in: defaults) ?? clayAccent }
    static func fill(in defaults: UserDefaults) -> NSColor { stored(in: defaults) ?? clayFill }

    /// The fill mixed 12% towards white on a dark theme, towards black on a light one.
    static func fillPressed(darkTheme: Bool) -> NSColor { fillPressed(darkTheme: darkTheme, fill: fill) }

    static func fillPressed(darkTheme: Bool, in defaults: UserDefaults) -> NSColor {
        fillPressed(darkTheme: darkTheme, fill: fill(in: defaults))
    }

    private static func fillPressed(darkTheme: Bool, fill: NSColor) -> NSColor {
        let target = darkTheme ? white : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        return SAClaudeEditorChrome.derivedColour(text: target, background: fill, ratio: pressedRatio)
    }

    /// The text colour on the fill: white, or near-black `#1A1A1A` when that has clearly more WCAG contrast.
    static func onAccent(in defaults: UserDefaults) -> NSColor { onAccent(fill: fill(in: defaults)) }

    static func onAccent(fill: NSColor) -> NSColor {
        let l = relativeLuminance(fill)
        let whiteContrast = 1.05 / (l + 0.05)
        let darkContrast = (l + 0.05) / (relativeLuminance(nearBlack) + 0.05)
        return darkContrast > whiteContrast * whitePreference ? nearBlack : white
    }

    /// WCAG relative luminance of the colour's sRGB value.
    static func relativeLuminance(_ colour: NSColor) -> CGFloat {
        guard let c = colour.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }
}
