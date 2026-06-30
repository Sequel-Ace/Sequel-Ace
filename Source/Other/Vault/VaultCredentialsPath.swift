//
//  VaultCredentialsPath.swift
//  Sequel Ace
//
//  Pure helpers to split/join the Vault database credentials path
//  (`<mount>/creds/<role>`) into its mount and role parts.
//

import Foundation

@objcMembers final class VaultCredentialsPath: NSObject {

    private static let separator = "/creds/"
    private static let slashes = CharacterSet(charactersIn: "/")

    /// Mount prefix (everything before `/creds/`). Empty when the path is unparseable.
    static func mount(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator) else { return "" }
        return String(p[..<range.lowerBound])
    }

    /// Role suffix (everything after `/creds/`). Falls back to the whole string
    /// when `/creds/` is absent, so a hand-typed value is never dropped.
    static func role(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator) else { return p }
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
