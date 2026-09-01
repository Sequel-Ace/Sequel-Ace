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

/// How Swift code obtains the keychain store.
///
/// SPKeychain's init returns nil while keychain access is disabled
/// (`LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN`, issue #2437); before the header was
/// annotated, that nil arrived through an `init!` import and trapped on
/// first use. The factory makes the disabled mode a real object instead —
/// callers always hold a working `SAKeychainProviding`.
///
/// App target only (it names SPKeychain, which the Unit Tests target cannot
/// see — no bridging header there). Once the SecItem* implementation
/// replaces SPKeychain (migration plan Step 5), this becomes its one
/// construction point.
enum SAKeychainAccess {

    static func make() -> SAKeychainProviding {
        // The as? is a real runtime conformance check: SPKeychain adopts the
        // protocol in a class extension inside its .m, which Swift cannot
        // see statically (the header cannot import the generated Swift
        // header that defines the protocol — that would be circular).
        if let store = SPKeychain(), let typed = store as? SAKeychainProviding {
            return typed
        }
        return SAKeychainDisabled()
    }
}
