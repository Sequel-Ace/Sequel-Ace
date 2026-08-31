//
//  SAKeychain.swift
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

import AppKit
import Foundation
import Security

/// The `SecItem*` implementation of the keychain store — SPKeychain's
/// replacement (migration plan Step 4).
///
/// It operates on the same physical store as the legacy `SecKeychain*` code:
/// the file-based login keychain (`kSecUseDataProtectionKeychain` is
/// deliberately never passed), so every existing user item is found, read,
/// updated and deleted **in place** — no data migration. The semantics are
/// pinned by `SAKeychainStoreCharacterizationTests`, which runs identically
/// against this class and against SPKeychain, plus the cross-implementation
/// matrix in `SAKeychainCrossCompatibilityTests` (legacy writes → this
/// reads, and the reverse).
///
/// Pinned behaviours worth naming: add is a silent no-op when the item
/// already exists (callers branch through the update path); update recovers
/// from a missing source (`errSecItemNotFound` → fresh add under the new
/// name) and from an occupied destination (`errSecDuplicateItem` → delete
/// it, retry once); a rename leaves the item's label behind; and
/// `SecItemUpdate` preserves an existing item's access list, which is what
/// keeps legacy-created items working.
@objc final class SAKeychain: NSObject, SAKeychainProviding {

    /// The literal the legacy code stored in `kSecGenericItemAttr` for every
    /// item; kept for item-shape parity.
    private static let genericAttribute = Data("application password".utf8)

    // MARK: - Store operations

    func add(password: String?, name: String?, account: String?) {
        add(password: password, name: name, account: account, label: name)
    }

    func add(password: String?, name: String?, account: String?, label: String?) {
        guard let name, let account, isValid(name: name, account: account), let password else { return }

        // Adding is a silent no-op when the item exists — callers rely on it.
        guard !passwordExists(name: name, account: account) else { return }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: label ?? "",
            kSecAttrGeneric as String: Self.genericAttribute,
            kSecValueData as String: Data(password.utf8),
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("Error (%i) while trying to add password for name: %@ account: %@", status, name, account)
            presentErrorSync(
                title: NSLocalizedString("Error adding password to Keychain", comment: "error adding password to keychain message"),
                message: String(format: NSLocalizedString("An error occurred while trying to add the password to your Keychain. Repairing your Keychain might resolve this, but if it doesn't please report it to the Sequel Ace team, supplying the error code %i.", comment: "error adding password to keychain informative message"), status)
            )
        }
    }

    func password(name: String?, account: String?) -> String? {
        guard let name, let account, isValid(name: name, account: account) else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deletePassword(name: String?, account: String?) {
        guard let name, let account, isValid(name: name, account: account) else { return }
        guard passwordExists(name: name, account: account) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess {
            NSLog("Error (%i) while trying to delete password for name: %@ account: %@", status, name, account)
        }
    }

    func passwordExists(name: String?, account: String?) -> Bool {
        guard let name, let account, isValid(name: name, account: account) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    func updateItem(name: String?, account: String?, toName newName: String?, newAccount: String?, password: String?) {
        guard let name, let account, isValid(name: name, account: account) else { return }
        guard let password else {
            NSLog("Keychain update rejected: nil password for name: %@ account: %@", name, account)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: account,
        ]
        // A nil new name/account writes an empty attribute, exactly as the
        // legacy zero-length SecKeychainAttribute did. The label is
        // deliberately not touched (renames leave it behind — pinned), and
        // SecItemUpdate preserves the item's access list.
        let changes: [String: Any] = [
            kSecAttrService as String: newName ?? "",
            kSecAttrAccount as String: newAccount ?? "",
            kSecValueData as String: Data(password.utf8),
        ]

        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)

        // The source item does not exist: try a safe delete, then a fresh
        // add under the new name and account (the legacy -25300 branch).
        if status == errSecItemNotFound {
            deletePassword(name: name, account: account)
            add(password: password, name: newName, account: newAccount)
            return
        }

        // The destination already exists: connection names carry a unique
        // id, so this indicates an earlier partial rename — delete the old
        // destination item and retry once (the legacy -25299 branch, minus
        // its unbounded recursion).
        if status == errSecDuplicateItem {
            deletePassword(name: newName, account: newAccount)
            status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        }

        if status != errSecSuccess {
            NSLog("Error (%i) while updating keychain item for name: %@ account: %@", status, name, account)
            presentErrorSync(
                title: NSLocalizedString("Error updating Keychain item", comment: "error updating keychain item message"),
                message: String(format: NSLocalizedString("An error occurred while trying to update the Keychain item. Repairing your Keychain might resolve this, but if it doesn't please report it to the Sequel Ace team, supplying the error code %i.", comment: "error updating keychain item informative message"), status)
            )
        }
    }

    // MARK: - Names and accounts

    func name(favoriteName: String?, id favoriteID: String?) -> String? {
        SAKeychainNaming.favoriteName(favoriteName, id: favoriteID)
    }

    func account(user: String?, host: String?, database: String?) -> String? {
        SAKeychainNaming.account(user: user, host: host, database: database)
    }

    func sshName(favoriteName: String?, id favoriteID: String?) -> String? {
        SAKeychainNaming.sshFavoriteName(favoriteName, id: favoriteID)
    }

    func sshAccount(user: String?, host: String?) -> String? {
        SAKeychainNaming.sshAccount(user: user, host: host)
    }

    // MARK: - Helpers

    private func isValid(name: String, account: String) -> Bool {
        !name.isEmpty && !account.isEmpty
    }

    /// Failure alerts present modally on the main thread, blocking the
    /// calling thread like the legacy inline runModal did (SPMainQSync
    /// semantics).
    private func presentErrorSync(title: String, message: String) {
        let present = {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
        }
        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.sync(execute: present)
        }
    }
}
