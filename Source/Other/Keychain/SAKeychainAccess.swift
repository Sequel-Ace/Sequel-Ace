//
//  SAKeychainAccess.swift
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

/// The one construction point for the keychain store, from Swift and
/// Objective-C alike.
///
/// Owns the issue #2437 guard: while `LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN` is
/// set, keychain access is disabled wholesale and callers receive the
/// `SAKeychainDisabled` null object — previously this guard was SPKeychain's
/// nil-returning init, which gave Objective-C callers nil-messaging no-ops
/// and trapped unguarded Swift callers. Callers always hold a working
/// `SAKeychainProviding` now.
@objc final class SAKeychainAccess: NSObject {

    @objc static func make() -> SAKeychainProviding {
        if ProcessInfo.processInfo.environment["LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN"] != nil {
            NSLog("LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN is set. Disabling keychain access. See Issue #2437")
            return SAKeychainDisabled()
        }
        return SAKeychain()
    }

    private override init() {}
}
