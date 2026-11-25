//
//  SADesignGlyphs.swift
//  Sequel Ace
//
//  The design-system 16pt outline icons, drawn from vector paths on a 16x16
//  grid (y down) so they stay sharp at any scale and re-tint for light/dark at
//  draw time. Pure AppKit, shared with Unit Tests.
//

import AppKit

/// The icons the design system draws.
@objc enum SADesignGlyph: Int {
    case database, table
    case structure, relations, triggers, info, query, recordView, users, console, clearConsole, chevronLeft, chevronRight
}

@objc final class SADesignGlyphs: NSObject {

    /// What VoiceOver reads for an icon.
    static func accessibilityName(for glyph: SADesignGlyph) -> String {
        switch glyph {
        case .database: return NSLocalizedString("Database", comment: "accessibility name of the database icon")
        case .table: return NSLocalizedString("Table", comment: "accessibility name of the table icon")
        case .structure: return NSLocalizedString("Structure", comment: "accessibility name of the table structure toolbar icon")
        case .relations: return NSLocalizedString("Relations", comment: "accessibility name of the table relations toolbar icon")
        case .triggers: return NSLocalizedString("Triggers", comment: "accessibility name of the table triggers toolbar icon")
        case .info: return NSLocalizedString("Table Info", comment: "accessibility name of the table info toolbar icon")
        case .query: return NSLocalizedString("Query", comment: "accessibility name of the query toolbar icon")
        case .recordView: return NSLocalizedString("Record View", comment: "accessibility name of the record view toolbar icon")
        case .users: return NSLocalizedString("Users", comment: "accessibility name of the user accounts toolbar icon")
        case .console: return NSLocalizedString("Console", comment: "accessibility name of the console toolbar icon")
        case .clearConsole: return NSLocalizedString("Clear Console", comment: "accessibility name of the clear console toolbar icon")
        case .chevronLeft: return NSLocalizedString("Back", comment: "accessibility name of the history back arrow in the main window toolbar")
        case .chevronRight: return NSLocalizedString("Forward", comment: "accessibility name of the history forward arrow in the main window toolbar")
        }
    }

    /// A 16pt icon in the given tint.
    @objc(imageForGlyph:tint:)
    static func image(_ glyph: SADesignGlyph, tint: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            // `tint` is dynamic: it resolves against the appearance current at draw time.
            tint.setStroke()
            for path in paths(for: glyph) {
                path.lineWidth = SADesignStyle.iconStrokeWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
        // Redraw on every use so an appearance change re-tints immediately.
        image.cacheMode = .never
        image.accessibilityDescription = accessibilityName(for: glyph)
        return image
    }

    // MARK: - Paths (16x16 grid, y down; built fresh on every call)

    private static func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

    private static func line(_ a: NSPoint, _ b: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        return path
    }

    static func paths(for glyph: SADesignGlyph) -> [NSBezierPath] {
        switch glyph {
        case .database:
            let top = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 1.5, width: 11, height: 4))
            let body = NSBezierPath()
            body.move(to: p(2.5, 3.5))
            body.line(to: p(2.5, 12.5))
            body.curve(to: p(8, 14.5), controlPoint1: p(2.5, 13.6), controlPoint2: p(5, 14.5))
            body.curve(to: p(13.5, 12.5), controlPoint1: p(11, 14.5), controlPoint2: p(13.5, 13.6))
            body.line(to: p(13.5, 3.5))
            let band = NSBezierPath()
            band.move(to: p(2.5, 8))
            band.curve(to: p(8, 10), controlPoint1: p(2.5, 9.1), controlPoint2: p(5, 10))
            band.curve(to: p(13.5, 8), controlPoint1: p(11, 10), controlPoint2: p(13.5, 9.1))
            return [top, body, band]
        case .table:
            return [NSBezierPath(roundedRect: NSRect(x: 2, y: 2.5, width: 12, height: 11), xRadius: 2, yRadius: 2),
                    line(p(2, 6.5), p(14, 6.5)), line(p(6.5, 6.5), p(6.5, 13.5))]
        case .structure:
            return [NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 11, height: 11), xRadius: 2, yRadius: 2),
                    line(p(2.5, 6), p(13.5, 6)), line(p(6.2, 6), p(6.2, 13.5)), line(p(9.8, 6), p(9.8, 13.5))]
        case .relations:
            return [line(p(3, 5.5), p(13, 5.5)), line(p(10.5, 3), p(13, 5.5)), line(p(13, 5.5), p(10.5, 8)),
                    line(p(13, 10.5), p(3, 10.5)), line(p(5.5, 8), p(3, 10.5)), line(p(3, 10.5), p(5.5, 13))]
        case .triggers:
            let bolt = NSBezierPath()
            bolt.move(to: p(9, 1.8)); bolt.line(to: p(4, 9)); bolt.line(to: p(7.8, 9))
            bolt.line(to: p(7, 14.2)); bolt.line(to: p(12, 7)); bolt.line(to: p(8.2, 7)); bolt.close()
            return [bolt]
        case .info:
            return [NSBezierPath(ovalIn: NSRect(x: 2.2, y: 2.2, width: 11.6, height: 11.6)),
                    line(p(8, 7.4), p(8, 11)), NSBezierPath(ovalIn: NSRect(x: 7.6, y: 4.6, width: 0.8, height: 0.8))]
        case .query:
            return [NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 10), xRadius: 2, yRadius: 2),
                    line(p(5, 6.5), p(7, 8)), line(p(7, 8), p(5, 9.5)), line(p(8.5, 10), p(11, 10))]
        case .recordView:
            return [NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 10), xRadius: 2, yRadius: 2),
                    line(p(9.5, 3), p(9.5, 13))]
        case .users:
            let body = NSBezierPath()
            body.move(to: p(2.5, 13)); body.curve(to: p(9.5, 13), controlPoint1: p(2.5, 8.6), controlPoint2: p(9.5, 8.6))
            let second = NSBezierPath()
            second.move(to: p(10.6, 9.3)); second.curve(to: p(13.5, 12.6), controlPoint1: p(12.8, 9.3), controlPoint2: p(13.5, 10.6))
            return [NSBezierPath(ovalIn: NSRect(x: 3.8, y: 3.2, width: 4.4, height: 4.4)), body,
                    NSBezierPath(ovalIn: NSRect(x: 9.2, y: 4.2, width: 3.6, height: 3.6)), second]
        case .console:
            return [NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 10), xRadius: 2, yRadius: 2),
                    line(p(2, 6), p(14, 6)), line(p(5, 8.2), p(6.6, 9.5)), line(p(6.6, 9.5), p(5, 10.8))]
        case .clearConsole:
            return [NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 10), xRadius: 2, yRadius: 2),
                    line(p(2, 6), p(14, 6)), line(p(6.5, 8), p(9.5, 11)), line(p(9.5, 8), p(6.5, 11))]
        case .chevronLeft:
            return [line(p(9.5, 4), p(6, 8)), line(p(6, 8), p(9.5, 12))]
        case .chevronRight:
            return [line(p(6.5, 4), p(10, 8)), line(p(10, 8), p(6.5, 12))]
        }
    }
}
