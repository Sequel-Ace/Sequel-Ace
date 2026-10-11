//
//  SAClaudeGlyphs.swift
//  Sequel Ace
//
//  The Claude-style 16pt outline icons for the left navigation, drawn from
//  vector paths on a 16x16 grid (y down) so they stay sharp at any scale and
//  re-tint for light/dark at draw time. Pure AppKit, shared with Unit Tests.
//

import AppKit

/// The icons the left navigation draws.
@objc enum SAClaudeGlyph: Int {
    case database, table, view, procedure, function, add, actions, refresh, infoPanel, more, favorite, history
}

@objc final class SAClaudeGlyphs: NSObject {

    /// The tint an icon uses: its object type's colour, or muted for bar buttons.
    static func tint(for glyph: SAClaudeGlyph) -> NSColor {
        switch glyph {
        case .database: return SAClaudeStyle.tintDatabase
        case .table: return SAClaudeStyle.tintTable
        case .view: return SAClaudeStyle.tintView
        case .procedure: return SAClaudeStyle.tintProcedure
        case .function: return SAClaudeStyle.tintFunction
        case .add, .actions, .refresh, .infoPanel, .more, .favorite, .history: return SAClaudeStyle.textMuted
        }
    }

    /// What VoiceOver reads for an icon.
    static func accessibilityName(for glyph: SAClaudeGlyph) -> String {
        switch glyph {
        case .database: return NSLocalizedString("Database", comment: "accessibility name of the database icon")
        case .table: return NSLocalizedString("Table", comment: "accessibility name of the table icon")
        case .view: return NSLocalizedString("ViewIconAccessibilityName", value: "View", comment: "accessibility name of the view icon in the tables list")
        case .procedure: return NSLocalizedString("Procedure", comment: "accessibility name of the stored procedure icon in the tables list")
        case .function: return NSLocalizedString("Function", comment: "accessibility name of the stored function icon in the tables list")
        case .add: return NSLocalizedString("Add table", comment: "accessibility name of the add table button below the tables list")
        case .actions: return NSLocalizedString("Table actions", comment: "accessibility name of the table actions menu button below the tables list")
        case .refresh: return NSLocalizedString("Refresh table list", comment: "accessibility name of the refresh button below the tables list")
        case .infoPanel: return NSLocalizedString("Toggle information panel", comment: "accessibility name of the button that shows or hides the table information panel")
        case .more: return NSLocalizedString("Editor options", comment: "accessibility name of the editor options menu button under the query editor")
        case .favorite: return NSLocalizedString("Query Favorites", comment: "accessibility name of the query favorites menu button under the query editor")
        case .history: return NSLocalizedString("Query History", comment: "accessibility name of the query history menu button under the query editor")
        }
    }

    /// A 16pt icon in the given tint.
    @objc(imageForGlyph:tint:)
    static func image(_ glyph: SAClaudeGlyph, tint: NSColor) -> NSImage {
        image(glyph, tint: tint, canvas: NSSize(width: 16, height: 16), glyphX: 0)
    }

    /// The icon for a tables-list row, on the padded canvas that positions it
    /// and the name (see `SAClaudeStyle.sidebarIconLeading`).
    ///
    /// - Parameter type: An `SPTableType` value. Keep in sync with SPTableType in
    ///   SPConstants.h: -1 none, 0 table, 1 view, 2 procedure, 3 function,
    ///   4 event, 5 table in a new database.
    /// - Returns: The image, or `nil` for a header row (-1).
    @objc(sidebarImageForTableType:)
    static func sidebarImage(forTableType type: Int) -> NSImage? {
        let glyph: SAClaudeGlyph
        switch type {
        case -1: return nil
        case 1: glyph = .view
        case 2: glyph = .procedure
        case 3: glyph = .function
        default: glyph = .table
        }
        return image(glyph, tint: tint(for: glyph),
                     canvas: NSSize(width: SAClaudeStyle.sidebarIconCanvasWidth, height: 16),
                     glyphX: SAClaudeStyle.sidebarIconLeading)
    }

    private static func image(_ glyph: SAClaudeGlyph, tint: NSColor, canvas: NSSize, glyphX: CGFloat) -> NSImage {
        let image = NSImage(size: canvas, flipped: true) { _ in
            // `tint` is dynamic: it resolves against the appearance current at draw time.
            tint.setStroke()
            let shift = AffineTransform(translationByX: glyphX, byY: 0)
            for path in paths(for: glyph) {
                path.transform(using: shift)
                path.lineWidth = SAClaudeStyle.iconStrokeWidth
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

    static func paths(for glyph: SAClaudeGlyph) -> [NSBezierPath] {
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
        case .view:
            let frame = NSBezierPath(roundedRect: NSRect(x: 2, y: 2.5, width: 12, height: 11), xRadius: 2, yRadius: 2)
            frame.setLineDash([2.2, 1.8], count: 2, phase: 0)
            let eye = NSBezierPath()
            eye.move(to: p(4.5, 8.5))
            eye.curve(to: p(8, 6.1), controlPoint1: p(5.5, 6.9), controlPoint2: p(6.7, 6.1))
            eye.curve(to: p(11.5, 8.5), controlPoint1: p(9.3, 6.1), controlPoint2: p(10.5, 6.9))
            eye.curve(to: p(8, 10.9), controlPoint1: p(10.5, 10.1), controlPoint2: p(9.3, 10.9))
            eye.curve(to: p(4.5, 8.5), controlPoint1: p(6.7, 10.9), controlPoint2: p(5.5, 10.1))
            eye.close()
            return [frame, eye, NSBezierPath(ovalIn: NSRect(x: 6.4, y: 6.9, width: 3.2, height: 3.2))]
        case .procedure:
            let left = NSBezierPath()
            left.move(to: p(5, 2.5))
            left.line(to: p(4, 2.5))
            left.curve(to: p(2.5, 4), controlPoint1: p(3.17, 2.5), controlPoint2: p(2.5, 3.17))
            left.line(to: p(2.5, 6.5))
            left.line(to: p(1.5, 8))
            left.line(to: p(2.5, 9.5))
            left.line(to: p(2.5, 12))
            left.curve(to: p(4, 13.5), controlPoint1: p(2.5, 12.83), controlPoint2: p(3.17, 13.5))
            left.line(to: p(5, 13.5))
            let right = NSBezierPath()
            right.move(to: p(11, 2.5))
            right.line(to: p(12, 2.5))
            right.curve(to: p(13.5, 4), controlPoint1: p(12.83, 2.5), controlPoint2: p(13.5, 3.17))
            right.line(to: p(13.5, 6.5))
            right.line(to: p(14.5, 8))
            right.line(to: p(13.5, 9.5))
            right.line(to: p(13.5, 12))
            right.curve(to: p(12, 13.5), controlPoint1: p(13.5, 12.83), controlPoint2: p(12.83, 13.5))
            right.line(to: p(11, 13.5))
            let play = NSBezierPath()
            play.move(to: p(6.8, 5.8))
            play.line(to: p(6.8, 10.2))
            play.line(to: p(10, 8))
            play.close()
            return [left, right, play]
        case .function:
            let stem = NSBezierPath()
            stem.move(to: p(10.5, 2.5))
            stem.curve(to: p(7.9, 4.9), controlPoint1: p(8.9, 2.5), controlPoint2: p(8.2, 3.4))
            stem.line(to: p(6.4, 11.6))
            stem.curve(to: p(4, 13.5), controlPoint1: p(6.1, 13), controlPoint2: p(5.4, 13.5))
            return [stem, line(p(5, 6.5), p(10, 6.5))]
        case .add:
            return [line(p(8, 3), p(8, 13)), line(p(3, 8), p(13, 8))]
        case .actions:
            return [NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 4, height: 4)),
                    line(p(8, 1.8), p(8, 3.5)), line(p(8, 12.5), p(8, 14.2)),
                    line(p(1.8, 8), p(3.5, 8)), line(p(12.5, 8), p(14.2, 8)),
                    line(p(3.6, 3.6), p(4.8, 4.8)), line(p(11.2, 11.2), p(12.4, 12.4)),
                    line(p(3.6, 12.4), p(4.8, 11.2)), line(p(11.2, 4.8), p(12.4, 3.6))]
        case .refresh:
            let arc = NSBezierPath()
            arc.appendArc(withCenter: p(8, 8), radius: 5, startAngle: 30, endAngle: 330, clockwise: false)
            return [arc, line(p(12.33, 5.5), p(12.6, 2.4)), line(p(12.33, 5.5), p(9.3, 4.9))]
        case .infoPanel:
            return [NSBezierPath(roundedRect: NSRect(x: 2, y: 2.5, width: 12, height: 11), xRadius: 2, yRadius: 2),
                    line(p(2, 10), p(14, 10))]
        case .more:
            return [NSBezierPath(ovalIn: NSRect(x: 2.75, y: 7.25, width: 1.5, height: 1.5)),
                    NSBezierPath(ovalIn: NSRect(x: 7.25, y: 7.25, width: 1.5, height: 1.5)),
                    NSBezierPath(ovalIn: NSRect(x: 11.75, y: 7.25, width: 1.5, height: 1.5))]
        case .favorite:
            let star = NSBezierPath()
            let points: [(CGFloat, CGFloat)] = [(8, 2.2), (9.7, 5.8), (13.6, 6.3), (10.7, 9.0), (11.4, 12.9),
                                                (8, 11), (4.6, 12.9), (5.3, 9.0), (2.4, 6.3), (6.3, 5.8)]
            star.move(to: p(points[0].0, points[0].1))
            for point in points.dropFirst() { star.line(to: p(point.0, point.1)) }
            star.close()
            return [star]
        case .history:
            let ring = NSBezierPath()
            ring.appendArc(withCenter: p(8, 8), radius: 5.5, startAngle: 180, endAngle: 135, clockwise: false)
            return [ring, line(p(2.5, 8), p(2.5, 5.3)), line(p(2.5, 8), p(5.1, 8)),
                    line(p(8, 5), p(8, 8.2)), line(p(8, 8.2), p(10, 9.5))]
        }
    }
}
