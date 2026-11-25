//
//  SAVividPalette.swift
//  Sequel Ace
//
//  The vivid palette's tint alphas: a color laid over a surface as a tint
//  uses the alpha of the appearance (the selected toolbar item's chip is the
//  accent at this alpha). Shared with the Unit Tests target.
//

import AppKit

enum SAVividColor {
    /// Alpha of the tint (the fill laid over a surface) in each appearance.
    static let tintAlphaDark: CGFloat = 0.16
    static let tintAlphaLight: CGFloat = 0.12
}
