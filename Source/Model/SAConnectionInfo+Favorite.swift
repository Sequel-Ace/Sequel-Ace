//
//  SAConnectionInfo+Favorite.swift
//  Sequel Ace
//
//  Created as part of the modernization effort (Phase D1).
//
//  Decodes a stored favorite dictionary into a typed SAConnectionInfo,
//  owning the defaulting rules that were previously inline in
//  -[SPConnectionController updateFavoriteSelection:] (missing name → "",
//  missing colorIndex → -1, missing useCompression → true, missing
//  awsProfile → "default", and so on). The controller populates its form
//  properties from the decoded info instead of repeating ?:-defaulting for
//  every key.
//
//  This file compiles into the Unit Tests target, which has no bridging
//  header, so the favorite dictionary keys are inlined as string literals
//  rather than referencing the SPFavorite*Key constants. They MUST stay in
//  sync with SPConstants.m (same pattern as SAViewMode / SADatabaseListManager;
//  the values are part of the favorites plist wire format and cannot change
//  without a migration anyway).
//
//  Deliberately NOT decoded here:
//  - password / sshPassword / keychain item names: they come from the
//    keychain (side-effectful lookups that stay in the controller).
//  - vaultPort / vaultOIDCMount: the controller applies the *raw* dictionary
//    values, because nil (key absent) drives the form's NSNullPlaceholder
//    ("443" / "oidc") and SAConnectionInfo's non-optional strings cannot
//    represent that distinction. The decoded info carries "" placeholders.
//

import Foundation

// MARK: - Favorite dictionary keys (inlined; keep in sync with SPConstants.m)

private enum FavoriteKey {
    static let id = "id"
    static let type = "type"
    static let name = "name"
    static let useAWSIAMAuth = "useAWSIAMAuth"
    static let host = "host"
    static let socket = "socket"
    static let user = "user"
    static let colorIndex = "colorIndex"
    static let port = "port"
    static let database = "database"
    static let useCompression = "useCompression"
    static let timeZoneMode = "timeZoneMode"
    static let timeZoneIdentifier = "timeZone"
    static let allowDataLocalInfile = "allowDataLocalInfile"
    static let enableClearTextPlugin = "enableClearTextPlugin"
    static let requestServerPublicKey = "requestServerPublicKey"
    static let awsRegion = "awsRegion"
    static let awsProfile = "awsProfile"
    static let vaultHost = "vaultHost"
    // Not decoded (see header) but written by the new-favorite template.
    static let vaultPort = "vaultPort"
    static let vaultOIDCMount = "vaultOIDCMount"
    static let vaultCredentialsPath = "vaultCredentialsPath"
    static let useSSL = "useSSL"
    static let sslKeyFileLocationEnabled = "sslKeyFileLocationEnabled"
    static let sslKeyFileLocation = "sslKeyFileLocation"
    static let sslCertificateFileLocationEnabled = "sslCertificateFileLocationEnabled"
    static let sslCertificateFileLocation = "sslCertificateFileLocation"
    static let sslCACertFileLocationEnabled = "sslCACertFileLocationEnabled"
    static let sslCACertFileLocation = "sslCACertFileLocation"
    static let sshHost = "sshHost"
    static let sshUser = "sshUser"
    static let sshKeyLocationEnabled = "sshKeyLocationEnabled"
    static let sshKeyLocation = "sshKeyLocation"
    static let sshPort = "sshPort"
    static let sshRemoteSocketPath = "sshRemoteSocketPath"
}

// MARK: - Lenient value readers

/// Favorites plists store numbers as NSNumber, but imported dictionaries can
/// carry numeric strings. The original ObjC code read everything through
/// -integerValue / -boolValue, which both NSNumber and NSString implement —
/// these helpers mirror that leniency.
private func intValue(_ value: Any?, default defaultValue: Int) -> Int {
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return (string as NSString).integerValue }
    return defaultValue
}

private func boolValue(_ value: Any?, default defaultValue: Bool) -> Bool {
    if let number = value as? NSNumber { return number.boolValue }
    if let string = value as? String { return (string as NSString).boolValue }
    return defaultValue
}

private func stringValue(_ value: Any?, default defaultValue: String) -> String {
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return defaultValue
}

// MARK: - SAConnectionInfo decoding

extension SAConnectionInfo {

    /// Decodes a favorite dictionary (as stored in the favorites plist) into
    /// a typed connection info, applying the historical defaulting rules of
    /// -[SPConnectionController updateFavoriteSelection:]. A nil or empty
    /// dictionary yields the same values the connection form shows for
    /// "no favorite selected".
    static func fromFavoriteDictionary(_ favorite: [AnyHashable: Any]?) -> SAConnectionInfo {
        let fav = favorite ?? [:]
        var info = SAConnectionInfo()

        // Connection type: unknown raw values fall back to TCP/IP (the
        // historical default for a missing key).
        let rawType = intValue(fav[FavoriteKey.type], default: SAConnectionType.tcpIP.rawValue)
        info.type = SAConnectionType(rawValue: rawType) ?? .tcpIP

        // Standard details
        info.name = stringValue(fav[FavoriteKey.name], default: "")
        info.host = stringValue(fav[FavoriteKey.host], default: "")
        info.socket = stringValue(fav[FavoriteKey.socket], default: "")
        info.user = stringValue(fav[FavoriteKey.user], default: "")
        info.colorIndex = intValue(fav[FavoriteKey.colorIndex], default: -1)
        info.port = stringValue(fav[FavoriteKey.port], default: "")
        info.database = stringValue(fav[FavoriteKey.database], default: "")
        info.useCompression = boolValue(fav[FavoriteKey.useCompression], default: true)

        // Time zone: the identifier only applies in fixed mode; the other
        // modes always clear it.
        let rawTimeZoneMode = intValue(fav[FavoriteKey.timeZoneMode],
                                       default: SAConnectionTimeZoneMode.useServerTZ.rawValue)
        info.timeZoneMode = SAConnectionTimeZoneMode(rawValue: rawTimeZoneMode) ?? .useServerTZ
        info.timeZoneIdentifier = info.timeZoneMode == .useFixedTZ
            ? stringValue(fav[FavoriteKey.timeZoneIdentifier], default: "")
            : ""

        // Special prefs (NSControlStateValue semantics: 0 = off, 1 = on)
        info.allowDataLocalInfile = intValue(fav[FavoriteKey.allowDataLocalInfile], default: 0)
        info.enableClearTextPlugin = intValue(fav[FavoriteKey.enableClearTextPlugin], default: 0)
        info.requestServerPublicKey = intValue(fav[FavoriteKey.requestServerPublicKey], default: 0)

        // AWS IAM: the toggle is derived from the connection type, not stored.
        info.useAWSIAMAuth = info.type == .awsIAM ? 1 : 0
        info.awsRegion = stringValue(fav[FavoriteKey.awsRegion], default: "")
        info.awsProfile = stringValue(fav[FavoriteKey.awsProfile], default: "default")

        // Vault (vaultPort / vaultOIDCMount intentionally not decoded — see header)
        info.vaultHost = stringValue(fav[FavoriteKey.vaultHost], default: "")
        info.vaultCredentialsPath = stringValue(fav[FavoriteKey.vaultCredentialsPath], default: "")

        // SSL
        info.useSSL = intValue(fav[FavoriteKey.useSSL], default: 0)
        info.sslKeyFileLocationEnabled = intValue(fav[FavoriteKey.sslKeyFileLocationEnabled], default: 0)
        info.sslKeyFileLocation = stringValue(fav[FavoriteKey.sslKeyFileLocation], default: "")
        info.sslCertificateFileLocationEnabled = intValue(fav[FavoriteKey.sslCertificateFileLocationEnabled], default: 0)
        info.sslCertificateFileLocation = stringValue(fav[FavoriteKey.sslCertificateFileLocation], default: "")
        info.sslCACertFileLocationEnabled = intValue(fav[FavoriteKey.sslCACertFileLocationEnabled], default: 0)
        info.sslCACertFileLocation = stringValue(fav[FavoriteKey.sslCACertFileLocation], default: "")

        // SSH
        info.sshHost = stringValue(fav[FavoriteKey.sshHost], default: "")
        info.sshUser = stringValue(fav[FavoriteKey.sshUser], default: "")
        info.sshKeyLocationEnabled = intValue(fav[FavoriteKey.sshKeyLocationEnabled], default: 0)
        info.sshKeyLocation = stringValue(fav[FavoriteKey.sshKeyLocation], default: "")
        info.sshPort = stringValue(fav[FavoriteKey.sshPort], default: "")
        info.sshRemoteSocketPath = stringValue(fav[FavoriteKey.sshRemoteSocketPath], default: "")

        return info
    }
}

// MARK: - ObjC bridge

extension SAConnectionInfoObjC {

    /// ObjC entry point for SPConnectionController: decode a favorite
    /// dictionary into a typed info object using the historical defaulting
    /// rules (see SAConnectionInfo.fromFavoriteDictionary).
    @objc(infoFromFavoriteDictionary:)
    class func info(fromFavoriteDictionary favorite: NSDictionary?) -> SAConnectionInfoObjC {
        SAConnectionInfoObjC(info: .fromFavoriteDictionary(favorite as? [AnyHashable: Any]))
    }

    /// Coerces a raw favorite-dictionary value to a string while preserving
    /// the nil-vs-empty distinction that `fromFavoriteDictionary` cannot
    /// represent. Used for vaultPort / vaultOIDCMount, where nil (key
    /// absent) drives the form's NSNullPlaceholder but a stored value —
    /// even an NSNumber from an imported favorite — must arrive as a
    /// string (the controller later sends -length to these properties).
    @objc(rawFavoriteString:)
    class func rawFavoriteString(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

// MARK: - Favorite dictionary templates (Phase D2)

extension SAConnectionInfoObjC {

    /// The plist dictionary for a brand-new favorite, as previously built
    /// inline in -[SPConnectionController addFavorite:]. The key set and
    /// values are part of the favorites wire format — note the historical
    /// quirks preserved deliberately:
    /// - no `useCompression` key (the decoder defaults it to true),
    /// - no SSL key/cert/CA *path* keys (only the enabled flags),
    /// - vaultPort / vaultOIDCMount stored as "" (not absent).
    @objc(defaultNewFavoriteDictionaryWithID:)
    class func defaultNewFavoriteDictionary(withID favoriteID: NSNumber) -> NSMutableDictionary {
        let off = NSNumber(value: 0)
        let favorite: [String: Any] = [
            FavoriteKey.name: NSLocalizedString("New Favorite", comment: "new favorite name"),
            FavoriteKey.type: NSNumber(value: 0),
            FavoriteKey.host: "",
            FavoriteKey.socket: "",
            FavoriteKey.user: "",
            FavoriteKey.colorIndex: NSNumber(value: -1),
            FavoriteKey.port: "",
            FavoriteKey.timeZoneMode: NSNumber(value: 0),
            FavoriteKey.timeZoneIdentifier: "",
            FavoriteKey.allowDataLocalInfile: off,
            FavoriteKey.enableClearTextPlugin: off,
            FavoriteKey.requestServerPublicKey: off,
            FavoriteKey.useAWSIAMAuth: off,
            FavoriteKey.awsRegion: "",
            FavoriteKey.awsProfile: "default",
            FavoriteKey.useSSL: off,
            FavoriteKey.sslKeyFileLocationEnabled: off,
            FavoriteKey.sslCertificateFileLocationEnabled: off,
            FavoriteKey.sslCACertFileLocationEnabled: off,
            FavoriteKey.database: "",
            FavoriteKey.sshHost: "",
            FavoriteKey.sshUser: "",
            FavoriteKey.sshKeyLocationEnabled: off,
            FavoriteKey.sshKeyLocation: "",
            FavoriteKey.sshPort: "",
            FavoriteKey.sshRemoteSocketPath: "",
            FavoriteKey.vaultHost: "",
            FavoriteKey.vaultPort: "",
            FavoriteKey.vaultOIDCMount: "",
            FavoriteKey.vaultCredentialsPath: "",
            FavoriteKey.id: favoriteID
        ]
        return NSMutableDictionary(dictionary: favorite)
    }

    /// A duplicate of an existing favorite dictionary: same values, a fresh
    /// unique ID, and the name suffixed for clarity ("<name> Copy", as
    /// previously built inline in -[SPConnectionController duplicateFavorite:]).
    /// The source dictionary is not modified.
    @objc(duplicatedFavoriteDictionaryFromFavorite:withID:)
    class func duplicatedFavoriteDictionary(fromFavorite favorite: NSDictionary?, withID favoriteID: NSNumber) -> NSMutableDictionary {
        let duplicate = favorite.map(NSMutableDictionary.init(dictionary:)) ?? NSMutableDictionary()
        duplicate[FavoriteKey.id] = favoriteID

        let name = stringValue(favorite?[FavoriteKey.name], default: "")
        duplicate[FavoriteKey.name] = String(
            format: NSLocalizedString("%@ Copy", comment: "Initial favourite name after duplicating a previous favourite"),
            name
        )

        return duplicate
    }
}
