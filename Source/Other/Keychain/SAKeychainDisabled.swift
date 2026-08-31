//
//  SAKeychainDisabled.swift
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

/// The null object for keychain access while it is disabled
/// (`LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN` is set — issue #2437, where SPKeychain
/// refuses to construct at all).
///
/// Its behaviour deliberately mirrors what Objective-C callers already get
/// from messaging the nil SPKeychain: every operation is a no-op, every
/// lookup returns nil or false — the naming helpers included. Swift callers
/// hold this instead of nil (previously the unannotated init imported as
/// `init!` and the first use trapped — defect 3 in the migration plan).
@objc final class SAKeychainDisabled: NSObject, SAKeychainProviding {

    func add(password: String?, name: String?, account: String?) {}

    func add(password: String?, name: String?, account: String?, label: String?) {}

    func password(name: String?, account: String?) -> String? { nil }

    func deletePassword(name: String?, account: String?) {}

    func passwordExists(name: String?, account: String?) -> Bool { false }

    func updateItem(name: String?, account: String?, toName newName: String?, newAccount: String?, password: String?) {}

    func name(favoriteName: String?, id favoriteID: String?) -> String? { nil }

    func account(user: String?, host: String?, database: String?) -> String? { nil }

    func sshName(favoriteName: String?, id favoriteID: String?) -> String? { nil }

    func sshAccount(user: String?, host: String?) -> String? { nil }
}
