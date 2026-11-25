//
//  SADesignAccent.swift
//  Sequel Ace
//
//  The accent color of the design system: the macOS accent color
//  (`NSColor.controlAccentColor`, the one chosen in System Settings). It is
//  dynamic: it follows light/dark live, and a System Settings change posts
//  `SADesignAccent.didChangeNotification`, which stylers observe through
//  `observe(_:_:)`. Accent text and glyphs go through `readableText` /
//  `readableGlyph`, so every accent reads on the surface under it.
//  Shared with the Unit Tests target.
//

import AppKit

@objc final class SADesignAccent: NSObject {

    /// Posted when the macOS accent color changes.
    static let didChangeNotification = Notification.Name("SADesignAccentDidChange")

    /// The accent: the macOS accent color. Dynamic (resolves per appearance and follows System Settings), so read it
    /// through a drawing appearance or `resolved(_:dark:)`.
    @objc static var accent: NSColor { .controlAccentColor }

    /// A change of the macOS accent color (System Settings): AppKit posts `NSColor.systemColorsDidChangeNotification`,
    /// and this turns it into `didChangeNotification`, which every styler that draws in the accent observes. Started by
    /// the first `observe`.
    private static let systemColorsObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: nil) { _ in
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Calls `handler` with `owner` (on the main thread) whenever the accent changes, for as long as `owner`
    /// lives: stylers refresh whatever they cache from the accent. The observer has no queue (a poster on
    /// another thread must not wait for main) and hops to main itself; it is removed when `owner` deallocates.
    static func observe<Owner: AnyObject>(_ owner: Owner, _ handler: @escaping (Owner) -> Void) {
        _ = systemColorsObserver
        let token = NotificationCenter.default.addObserver(forName: didChangeNotification, object: nil, queue: nil) { [weak owner] _ in
            let run = {
                if let owner { handler(owner) }
            }
            if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
        }
        let lifetime: ObserverLifetime
        if let existing = objc_getAssociatedObject(owner, &lifetimeKey) as? ObserverLifetime {
            lifetime = existing
        } else {
            lifetime = ObserverLifetime()
            objc_setAssociatedObject(owner, &lifetimeKey, lifetime, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        lifetime.tokens.append(token)
    }

    private static var lifetimeKey: UInt8 = 0

    /// Held by the observing owner; its deinit removes the owner's observers.
    private final class ObserverLifetime {
        var tokens: [NSObjectProtocol] = []
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }

    /// `color` as an sRGB value in the light or dark appearance. A dynamic color (the macOS accent) is fixed here;
    /// a component color comes back unchanged. For code that measures or caches an accent outside a draw.
    static func resolved(_ color: NSColor, dark: Bool) -> NSColor {
        guard color.type != .componentBased else { return color }
        var result = color
        (NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }

    /// WCAG relative luminance of the color's sRGB value.
    static func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    // MARK: - Readable accent text and glyphs

    /// WCAG AA for body text (1.4.3): the contrast accent text keeps against its surface.
    static let readableContrast: CGFloat = 4.5
    /// WCAG AA for non-text (1.4.11): the contrast an accent glyph or icon keeps against its surface.
    static let glyphContrast: CGFloat = 3
    /// Where black and white have the same contrast: below it lighten, above it darken.
    private static let darkSurfaceLuminance: CGFloat = 0.179

    /// WCAG contrast ratio of two colors, 1...21.
    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The accent as text, in the light or dark appearance, on each of `backgrounds` (the surface, and any fill the
    /// text can also sit on, such as a row's highlight): at least `readableContrast` on every one. Every color is
    /// resolved in that appearance; pass the opaque color a reader sees (`composite(_:over:dark:)` for a translucent
    /// fill), and backgrounds that are all light or all dark. `accent` is the current accent unless given.
    static func readableText(on backgrounds: NSColor..., dark: Bool, accent: NSColor = SADesignAccent.accent) -> NSColor {
        readableAccent(accent, on: backgrounds, dark: dark, minimumContrast: readableContrast)
    }

    /// The accent as a glyph or icon (a tick, a toolbar glyph): as `readableText`, at `glyphContrast`.
    static func readableGlyph(on backgrounds: NSColor..., dark: Bool, accent: NSColor = SADesignAccent.accent) -> NSColor {
        readableAccent(accent, on: backgrounds, dark: dark, minimumContrast: glyphContrast)
    }

    private static func readableAccent(_ accent: NSColor, on backgrounds: [NSColor], dark: Bool, minimumContrast: CGFloat) -> NSColor {
        backgrounds.reduce(resolved(accent, dark: dark)) { readable($0, on: resolved($1, dark: dark), minimumContrast: minimumContrast) }
    }

    /// `top` drawn over `bottom`, both resolved in the light or dark appearance: the opaque sRGB color a translucent
    /// fill shows.
    static func composite(_ top: NSColor, over bottom: NSColor, dark: Bool) -> NSColor {
        guard let t = resolved(top, dark: dark).usingColorSpace(.sRGB),
              let b = resolved(bottom, dark: dark).usingColorSpace(.sRGB) else { return top }
        let a = t.alphaComponent
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x * a + y * (1 - a) }
        return NSColor(srgbRed: mix(t.redComponent, b.redComponent), green: mix(t.greenComponent, b.greenComponent),
                       blue: mix(t.blueComponent, b.blueComponent), alpha: 1)
    }

    /// `color` itself when it reads on `background` (contrast ≥ `minimumContrast`, by default the body-text 4.5), else
    /// the same hue and saturation with the HSB brightness stepped down (up, on a dark background) until it does. On a
    /// dark background that brightness alone can't lift (a pure blue), the saturation is then stepped down too. Both
    /// colors are taken as they are (resolve a dynamic one first).
    static func readable(_ color: NSColor, on background: NSColor, minimumContrast: CGFloat = readableContrast) -> NSColor {
        guard contrast(color, background) < minimumContrast, let rgb = color.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        func made() -> NSColor {
            NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha).usingColorSpace(.sRGB) ?? rgb
        }
        var result = rgb
        if relativeLuminance(background) < darkSurfaceLuminance {
            while brightness < 1, contrast(result, background) < minimumContrast {
                brightness = min(1, brightness + 0.01)
                result = made()
            }
            while saturation > 0, contrast(result, background) < minimumContrast {
                saturation = max(0, saturation - 0.01)
                result = made()
            }
        } else {
            while brightness > 0, contrast(result, background) < minimumContrast {
                brightness = max(0, brightness - 0.01)
                result = made()
            }
        }
        return result
    }
}
