//
//  SAClaudeClassSwap.swift
//  Sequel Ace
//
//  The one rule every Claude styler that swaps an object's class
//  (`object_setClass`) follows. Shared with the Unit Tests target.
//

import Foundation

enum SAClaudeClassSwap {

    /// Whether `object`'s class may be swapped: only while nothing observes it by KVO. KVO finds an observance by
    /// the observed object's class, so after a swap the observer's removal throws (an NSStackView dropping an
    /// arranged button it observes, for one). `observationInfo` is used rather than the class, because Swift's
    /// `type(of:)` does not show KVO's runtime subclass.
    static func mayChangeClass(of object: NSObject) -> Bool {
        object.observationInfo == nil
    }
}
