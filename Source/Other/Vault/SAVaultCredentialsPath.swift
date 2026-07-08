//
//  SAVaultCredentialsPath.swift
//  Sequel Ace
//
//  Pure helpers to split/join the Vault database credentials path
//  (`<mount>/creds/<role>`) into its mount and role parts.
//

import Foundation

@objcMembers final class SAVaultCredentialsPath: NSObject {

    private static let separator = "/creds/"
    private static let slashes = CharacterSet(charactersIn: "/")

    /// Mount prefix (everything before the final `/creds/`). Empty when the path is
    /// unparseable. Splitting on the last separator keeps a mount that itself
    /// contains a `creds` segment intact (e.g. `team/creds/mysql/creds/ro`).
    static func mount(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator, options: .backwards) else { return "" }
        return String(p[..<range.lowerBound])
    }

    /// Role suffix (everything after the final `/creds/`). Falls back to the whole
    /// string when `/creds/` is absent, so a hand-typed value is never dropped.
    static func role(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator, options: .backwards) else { return p }
        return String(p[range.upperBound...])
    }

    /// Rebuild `<mount>/creds/<role>`. Returns "" when role is empty; returns the
    /// role verbatim when mount is empty (lets a user paste a full path).
    static func credPath(mount: String, role: String) -> String {
        let m = mount.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: slashes)
        let r = role.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: slashes)
        if r.isEmpty { return "" }
        if m.isEmpty { return r }
        return "\(m)\(separator)\(r)"
    }
}
