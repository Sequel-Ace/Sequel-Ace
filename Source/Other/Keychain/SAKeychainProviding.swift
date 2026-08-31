//
//  SAKeychainProviding.swift
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

/// The keychain store surface — implemented by `SAKeychain` (SecItem*) and
/// `SAKeychainDisabled`, constructed via `SAKeychainAccess.make()`. See
/// `docs/development/keychain-secitem-migration-plan.md`.
///
/// The selectors are the legacy SPKeychain's, unchanged: that class adopted
/// this protocol untouched while the migration's cross-compatibility matrix
/// proved the two implementations equivalent, and the Objective-C call
/// sites still speak these exact selectors through the protocol today.
///
/// Public rather than internal so it is emitted into a generated
/// `sequel-ace-Swift.h` even for targets without an Objective-C bridging
/// header (only public declarations are emitted there).
@objc public protocol SAKeychainProviding {

    /// Adds a password with the item's label defaulting to `name`.
    /// Silently does nothing when an item for (`name`, `account`) already
    /// exists, or when any argument is nil/empty.
    @objc(addPassword:forName:account:)
    func add(password: String?, name: String?, account: String?)

    /// Adds a password with an explicit item label (nil label → empty).
    @objc(addPassword:forName:account:withLabel:)
    func add(password: String?, name: String?, account: String?, label: String?)

    /// Returns the stored password, or nil when the item does not exist or
    /// the arguments are nil/empty.
    @objc(getPasswordForName:account:)
    func password(name: String?, account: String?) -> String?

    /// Deletes the item when it exists; otherwise does nothing.
    @objc(deletePasswordForName:account:)
    func deletePassword(name: String?, account: String?)

    @objc(passwordExistsForName:account:)
    func passwordExists(name: String?, account: String?) -> Bool

    /// Renames an item and replaces its password in place (preserving its
    /// access list). Falls back to add when the source item is missing, and
    /// replaces the destination when it already exists.
    @objc(updateItemWithName:account:toName:account:password:)
    func updateItem(name: String?, account: String?, toName newName: String?, newAccount: String?, password: String?)

    /// `"Sequel Ace : <favoriteName> (<id as long long>)"`, or nil for a
    /// nil/empty name or nil id. The id is `Any?` because the legacy method
    /// took `(id)` and Objective-C call sites hand over the favorites
    /// dictionary's NSNumber as often as a string — both are coerced through
    /// `-longLongValue` semantics.
    @objc(nameForFavoriteName:id:)
    func name(favoriteName: String?, id favoriteID: Any?) -> String?

    /// `"<user>@<host>/<database>"` (nil database → empty), or nil for a
    /// nil/empty user or host.
    @objc(accountForUser:host:database:)
    func account(user: String?, host: String?, database: String?) -> String?

    /// `"Sequel Ace SSHTunnel : <favoriteName> (<id as long long>)"`, or nil
    /// for a nil/empty name or nil id. Same `Any?` id contract as
    /// `name(favoriteName:id:)`.
    @objc(nameForSSHForFavoriteName:id:)
    func sshName(favoriteName: String?, id favoriteID: Any?) -> String?

    /// `"<user>@<host>"`, or nil for a nil/empty user or host.
    @objc(accountForSSHUser:sshHost:)
    func sshAccount(user: String?, host: String?) -> String?
}
