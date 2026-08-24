//
//  SAFavoriteDuplicateMatcher.swift
//  Sequel Ace
//
//  Item 4 of the modernization plan (SPConnectionController re-containment):
//  the pure logic behind connection-import duplicate detection, lifted out of
//  SPConnectionController. The controller keeps only what needs live objects —
//  the SPTreeNode walk over the favorites tree, the alert UI, and the keychain
//  side effects of applying an update.
//
//  Pure Foundation, compiled into BOTH the app and Unit Tests targets. The
//  favorite keys are inlined string literals so the file stays test-eligible
//  (no bridging header in the test target); keep them in sync with
//  SPConstants.m, same pattern as SAConnectionInfo+Favorite.
//

import Foundation

@objc final class SAFavoriteDuplicateMatcher: NSObject {

    // MARK: - Favorite keys (keep in sync with SPConstants.m)

    private enum FavoriteKey {
        static let id = "id"
        static let name = "name"
        static let host = "host"
        static let user = "user"
        static let database = "database"
        static let port = "port"
        static let type = "type"
        static let socket = "socket"
        static let sshHost = "sshHost"
        static let sshUser = "sshUser"
        static let sshPort = "sshPort"
        static let sshRemoteSocketPath = "sshRemoteSocketPath"
        static let awsRegion = "awsRegion"
        static let awsProfile = "awsProfile"
    }

    // MARK: - Connection-type mapping

    // Raw values mirror SPConnectionType in SPConstants.h.
    private static let tcpIPTag = 0
    private static let socketTag = 1
    private static let sshTunnelTag = 2
    private static let awsIAMTag = 3

    /// The tag for a connection-type string, defaulting to TCP/IP.
    ///
    /// ⚠️ Deliberate quirk, preserved from the original: Vault has no string of
    /// its own here, so a Vault favorite maps through the TCP/IP default in
    /// both directions and therefore *compares as TCP/IP* for duplicate
    /// purposes. Changing that changes which imports are flagged as duplicates.
    @objc(typeTagForString:)
    static func typeTag(forString typeString: String?) -> Int {
        switch typeString {
        case "SPSocketConnection": return socketTag
        case "SPSSHTunnelConnection": return sshTunnelTag
        case "SPAWSIAMConnection": return awsIAMTag
        default: return tcpIPTag
        }
    }

    /// The string for a connection-type tag; unknown tags (including Vault's 4)
    /// fall through to TCP/IP — see the quirk note on `typeTag(forString:)`.
    @objc(typeStringForTag:)
    static func typeString(forTag tag: Int) -> String {
        switch tag {
        case socketTag: return "SPSocketConnection"
        case sshTunnelTag: return "SPSSHTunnelConnection"
        case awsIAMTag: return "SPAWSIAMConnection"
        default: return "SPTCPIPConnection"
        }
    }

    // MARK: - Port normalization

    /// A port value as the string used for duplicate comparison.
    ///
    /// Favorites store ports as either NSNumber or NSString, so both spellings
    /// of the same port must compare equal. An empty port means the MySQL
    /// default, so it normalizes to "3306" — except for socket connections,
    /// where the port is irrelevant and an empty value stays empty.
    @objc(normalizedPort:typeString:)
    static func normalizedPort(_ port: Any?, typeString: String) -> String {
        let portString: String
        switch port {
        case let number as NSNumber:
            portString = number.stringValue
        case let string as String:
            portString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            portString = ""
        }

        if typeTag(forString: typeString) == socketTag {
            return portString
        }
        return portString.isEmpty ? "3306" : portString
    }

    // MARK: - The duplicate predicate

    /// Whether an existing favorite dictionary matches an import candidate.
    ///
    /// The base comparison is host, user, database, normalized port and
    /// connection type. When `modeSpecificFields` is supplied, the candidate's
    /// per-type details must match too:
    ///   - SSH tunnel: ssh host / user / port / remote socket path
    ///   - socket: the socket path
    ///   - AWS IAM: region and profile
    /// Each candidate field is read under its connection-string URL key first
    /// and its favorite-plist key second, because both import paths funnel into
    /// this predicate. Vault has no per-type comparison (see the type-mapping
    /// quirk); passing nil skips the per-type comparison entirely, which is how
    /// the URL-import path calls it after matching those fields itself.
    @objc(favorite:isDuplicateOfHost:user:database:port:typeString:modeSpecificFields:)
    static func favorite(_ existing: NSDictionary,
                         isDuplicateOfHost candidateHost: String,
                         user candidateUser: String,
                         database candidateDatabase: String,
                         port candidatePort: String,
                         typeString candidateType: String,
                         modeSpecificFields modeFields: NSDictionary?) -> Bool {
        let existingType = typeString(forTag: intValue(existing[FavoriteKey.type]))

        guard string(existing[FavoriteKey.host]) == candidateHost,
              string(existing[FavoriteKey.user]) == candidateUser,
              string(existing[FavoriteKey.database]) == candidateDatabase,
              normalizedPort(existing[FavoriteKey.port], typeString: existingType)
                  == normalizedPort(candidatePort, typeString: candidateType),
              existingType == candidateType else {
            return false
        }

        guard let modeFields else { return true }

        switch typeTag(forString: candidateType) {
        case sshTunnelTag:
            return string(existing[FavoriteKey.sshHost]) == candidateValue(modeFields, urlKey: "ssh_host", favoriteKey: FavoriteKey.sshHost)
                && string(existing[FavoriteKey.sshUser]) == candidateValue(modeFields, urlKey: "ssh_user", favoriteKey: FavoriteKey.sshUser)
                && string(existing[FavoriteKey.sshPort]) == candidateValue(modeFields, urlKey: "ssh_port", favoriteKey: FavoriteKey.sshPort)
                && string(existing[FavoriteKey.sshRemoteSocketPath]) == candidateValue(modeFields, urlKey: "ssh_remote_socket_path", favoriteKey: FavoriteKey.sshRemoteSocketPath)
        case socketTag:
            return string(existing[FavoriteKey.socket]) == candidateValue(modeFields, urlKey: "socket", favoriteKey: FavoriteKey.socket)
        case awsIAMTag:
            return string(existing[FavoriteKey.awsRegion]) == candidateValue(modeFields, urlKey: "aws_region", favoriteKey: FavoriteKey.awsRegion)
                && string(existing[FavoriteKey.awsProfile]) == candidateValue(modeFields, urlKey: "aws_profile", favoriteKey: FavoriteKey.awsProfile)
        default:
            return true
        }
    }

    // MARK: - Applying an update to a duplicate

    /// The existing favorite with every field from `newData` applied — except
    /// the name and the ID, which stay with the favorite being updated. That is
    /// what makes "Update" on a duplicate an update rather than a replacement:
    /// the favorite keeps its identity (and thus its keychain entry naming) and
    /// its user-chosen name, while the connection details are refreshed.
    @objc(mergedFavoriteFrom:applying:)
    static func mergedFavorite(from existing: NSDictionary, applying newData: NSDictionary) -> NSMutableDictionary {
        let merged = NSMutableDictionary(dictionary: existing)
        for case let (key as String, value) in newData {
            if key == FavoriteKey.name || key == FavoriteKey.id { continue }
            merged[key] = value
        }
        return merged
    }

    // MARK: - Lenient value readers

    /// A dictionary value as a string, "" when absent or not a string —
    /// mirroring the original's `objectForKey: ?: @""` defaulting. (The ObjC
    /// would have thrown on a non-string; reading it as absent is the lenient
    /// side of the same rule.)
    private static func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    /// ObjC `-integerValue` leniency for the type field: NSNumber or numeric
    /// NSString, anything else 0 (TCP/IP).
    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text) ?? 0
        default: return 0
        }
    }

    /// A candidate mode field, read under the connection-string URL key first
    /// and the favorite-plist key second.
    private static func candidateValue(_ fields: NSDictionary, urlKey: String, favoriteKey: String) -> String {
        (fields[urlKey] as? String) ?? (fields[favoriteKey] as? String) ?? ""
    }
}
