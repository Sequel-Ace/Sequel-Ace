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

/// The keychain surface shared by the legacy `SPKeychain` (Objective-C,
/// `SecKeychain*`) and its planned `SecItem*` replacement — see
/// `docs/development/keychain-secitem-migration-plan.md`.
///
/// The selectors mirror `SPKeychain.h` exactly so the legacy class conforms
/// without any change to its methods; the characterization suite is written
/// against this protocol so the identical tests can later run against both
/// implementations (the migration plan's cross-compatibility matrix).
///
/// Public rather than internal so it appears in every target's generated
/// `sequel-ace-Swift.h` — `SPKeychain.m` compiles into the app, the
/// SequelAceTunnelAssistant, and (for the characterization suite) the Unit
/// Tests target, and only public declarations are emitted into the generated
/// header for targets that have no Objective-C bridging header.
@objc public protocol SAKeychainProviding {

    /// Adds a password with the item's label defaulting to `name`.
    /// Silently does nothing when an item for (`name`, `account`) already
    /// exists, when the name or account is nil/empty, or when the password
    /// is nil — an *empty* password is stored (and round-trips as `""`).
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
    /// nil/empty name or nil id.
    @objc(nameForFavoriteName:id:)
    func name(favoriteName: String?, id favoriteID: String?) -> String?

    /// `"<user>@<host>/<database>"` (nil database → empty), or nil for a
    /// nil/empty user or host.
    @objc(accountForUser:host:database:)
    func account(user: String?, host: String?, database: String?) -> String?

    /// `"Sequel Ace SSHTunnel : <favoriteName> (<id as long long>)"`, or nil
    /// for a nil/empty name or nil id.
    @objc(nameForSSHForFavoriteName:id:)
    func sshName(favoriteName: String?, id favoriteID: String?) -> String?

    /// `"<user>@<host>"`, or nil for a nil/empty user or host.
    @objc(accountForSSHUser:sshHost:)
    func sshAccount(user: String?, host: String?) -> String?
}
