//
//  SASpacing.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.10.27.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import CoreGraphics

/// Spacing steps for new Swift UI, so layouts share one scale instead of raw numbers.
///
/// All steps sit on a 4-pt grid. Foundation only, so it is also compiled into
/// the Unit Tests target.
enum SASpacing {
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 24
}
