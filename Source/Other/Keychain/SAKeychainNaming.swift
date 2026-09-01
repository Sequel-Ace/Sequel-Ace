//
//  SAKeychainNaming.swift
//  Sequel Ace
//
//  Created by the Sequel Ace team on August 31, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
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
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Foundation

/// The four keychain name/account formats — the keychain wire format.
///
/// These strings are persisted in every user's login keychain (and `.spf`
/// documents carry them verbatim), so they are byte-pinned by
/// `SAKeychainNamingCharacterizationTests` and must never drift. The rules,
/// inherited from SPKeychain:
///
/// - ids are coerced through `NSString.longLongValue` (non-numeric → 0,
///   numeric prefixes parsed as far as they go, 64-bit clamped) — "to
///   support 64-bit > 32-bit keychain usage" per the original comment;
/// - a nil or empty favorite name / user / host rejects the whole lookup
///   (nil result); a nil id likewise;
/// - a nil database is an empty string (trailing slash kept).
///
/// Pure Foundation; compiles into the app and Unit Tests targets.
enum SAKeychainNaming {

    /// `"Sequel Ace : <favoriteName> (<id>)"`
    static func favoriteName(_ favoriteName: String?, id favoriteID: String?) -> String? {
        guard let favoriteName, !favoriteName.isEmpty, let favoriteID else { return nil }
        return "Sequel Ace : \(favoriteName) (\((favoriteID as NSString).longLongValue))"
    }

    /// `"<user>@<host>/<database>"`
    static func account(user: String?, host: String?, database: String?) -> String? {
        guard let user, !user.isEmpty, let host, !host.isEmpty else { return nil }
        return "\(user)@\(host)/\(database ?? "")"
    }

    /// `"Sequel Ace SSHTunnel : <favoriteName> (<id>)"`
    static func sshFavoriteName(_ favoriteName: String?, id favoriteID: String?) -> String? {
        guard let favoriteName, !favoriteName.isEmpty, let favoriteID else { return nil }
        return "Sequel Ace SSHTunnel : \(favoriteName) (\((favoriteID as NSString).longLongValue))"
    }

    /// `"<user>@<host>"`
    static func sshAccount(user: String?, host: String?) -> String? {
        guard let user, !user.isEmpty, let host, !host.isEmpty else { return nil }
        return "\(user)@\(host)"
    }
}
