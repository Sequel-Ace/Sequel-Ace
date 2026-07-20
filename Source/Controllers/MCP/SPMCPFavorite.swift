//
//  SPMCPFavorite.swift
//  Sequel Ace
//
//  Pure helpers for describing the favorite a connection was opened from,
//  used by the MCP list_connections tool.
//  Copyright (c) 2024 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

enum SPMCPFavorite {

    /// Joins ancestor group names (outermost first) and the favorite name into a
    /// path like "Group/Subgroup/Favorite". Empty group names are dropped.
    static func pathString(groups: [String], favoriteName: String) -> String {
        return (groups.filter { !$0.isEmpty } + [favoriteName]).joined(separator: "/")
    }

    /// Normalizes a favorite id, which the favorites plist stores as a number but
    /// the live connection carries as a string, to a string for comparison.
    static func idString(_ value: Any?) -> String? {
        switch value {
        case let number as NSNumber:
            return number.stringValue
        case let string as String:
            return string.isEmpty ? nil : string
        default:
            return nil
        }
    }
}
