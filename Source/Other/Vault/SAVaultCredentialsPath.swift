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

    /// Normalize a Vault mount: trim surrounding whitespace, then strip leading and
    /// trailing slashes. Shared by `credPath(mount:role:)` and the role LIST request
    /// so the mount the UI joins into the path matches the mount the client queries.
    static func normalizeMount(_ mount: String) -> String {
        return mount.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: slashes)
    }

    /// Mount prefix (everything before the final `/creds/`). Empty when the path is
    /// unparseable. Splitting on the last separator keeps a mount that itself
    /// contains a `creds` segment intact (e.g. `team/creds/mysql/creds/ro`).
    static func mount(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator, options: .backwards) else { return "" }
        return String(p[..<range.lowerBound])
    }

    /// Whether `value` already contains the `/creds/` separator, i.e. it looks like
    /// a full credentials path (e.g. pasted into the Role field) rather than a bare
    /// role name. Used to decide when to split it back into Mount + Role.
    static func isFullCredPath(_ value: String) -> Bool {
        return value.range(of: separator) != nil
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
        let m = normalizeMount(mount)
        let r = role.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: slashes)
        if r.isEmpty { return "" }
        // A role that itself contains "/creds/" is already a full credentials path
        // (e.g. pasted into the Role field, which the UI explicitly invites). Honor
        // it verbatim instead of prefixing the mount, which would double the path
        // into "<mount>/creds/<mount>/creds/<role>".
        if r.range(of: separator) != nil { return r }
        if m.isEmpty { return r }
        return "\(m)\(separator)\(r)"
    }
}
