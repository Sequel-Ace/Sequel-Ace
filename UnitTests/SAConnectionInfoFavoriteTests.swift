//
//  SAConnectionInfoFavoriteTests.swift
//  Unit Tests
//
//  Pins the favorite-dictionary → SAConnectionInfo defaulting rules lifted
//  out of -[SPConnectionController updateFavoriteSelection:] (Phase D1).
//  The key literals here intentionally mirror the favorites plist wire
//  format (SPConstants.m) — if one of these tests breaks, favorites
//  written by released versions would decode differently on upgrade.
//

import XCTest

final class SAConnectionInfoFavoriteTests: XCTestCase {

    // MARK: - Defaults (nil / empty dictionary)

    func testNilDictionaryYieldsFormDefaults() {
        let info = SAConnectionInfo.fromFavoriteDictionary(nil)

        XCTAssertEqual(info.type, .tcpIP)
        XCTAssertEqual(info.name, "")
        XCTAssertEqual(info.host, "")
        XCTAssertEqual(info.socket, "")
        XCTAssertEqual(info.user, "")
        XCTAssertEqual(info.colorIndex, -1)
        XCTAssertEqual(info.port, "")
        XCTAssertEqual(info.database, "")
        XCTAssertTrue(info.useCompression)
        XCTAssertEqual(info.timeZoneMode, .useServerTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "")
        XCTAssertEqual(info.allowDataLocalInfile, 0)
        XCTAssertEqual(info.enableClearTextPlugin, 0)
        XCTAssertEqual(info.requestServerPublicKey, 0)
        XCTAssertEqual(info.useAWSIAMAuth, 0)
        XCTAssertEqual(info.awsRegion, "")
        XCTAssertEqual(info.awsProfile, "default")
        XCTAssertEqual(info.vaultHost, "")
        XCTAssertEqual(info.vaultCredentialsPath, "")
        XCTAssertEqual(info.useSSL, 0)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 0)
        XCTAssertEqual(info.sslKeyFileLocation, "")
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 0)
        XCTAssertEqual(info.sslCertificateFileLocation, "")
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 0)
        XCTAssertEqual(info.sslCACertFileLocation, "")
        XCTAssertEqual(info.sshHost, "")
        XCTAssertEqual(info.sshUser, "")
        XCTAssertEqual(info.sshKeyLocationEnabled, 0)
        XCTAssertEqual(info.sshKeyLocation, "")
        XCTAssertEqual(info.sshPort, "")
        XCTAssertEqual(info.sshRemoteSocketPath, "")
    }

    func testEmptyDictionaryMatchesNilDictionary() {
        let fromNil = SAConnectionInfo.fromFavoriteDictionary(nil)
        let fromEmpty = SAConnectionInfo.fromFavoriteDictionary([:])

        XCTAssertEqual(fromEmpty.type, fromNil.type)
        XCTAssertEqual(fromEmpty.colorIndex, fromNil.colorIndex)
        XCTAssertEqual(fromEmpty.useCompression, fromNil.useCompression)
        XCTAssertEqual(fromEmpty.awsProfile, fromNil.awsProfile)
        XCTAssertEqual(fromEmpty.timeZoneMode, fromNil.timeZoneMode)
    }

    func testPasswordAndKeychainFieldsAreNeverDecoded() {
        // Passwords come from the keychain, not the favorites plist.
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "password": "secret", "sshPassword": "tunnel-secret"
        ])

        XCTAssertEqual(info.password, "")
        XCTAssertEqual(info.sshPassword, "")
        XCTAssertEqual(info.connectionKeychainItemName, "")
        XCTAssertEqual(info.connectionSSHKeychainItemName, "")
    }

    // MARK: - Standard details

    func testStandardDetailsDecodeFromDictionary() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "type": NSNumber(value: 0),
            "name": "Prod",
            "host": "db.example.com",
            "socket": "/tmp/mysql.sock",
            "user": "app",
            "colorIndex": NSNumber(value: 3),
            "port": "3307",
            "database": "shop",
            "useCompression": NSNumber(value: false)
        ])

        XCTAssertEqual(info.type, .tcpIP)
        XCTAssertEqual(info.name, "Prod")
        XCTAssertEqual(info.host, "db.example.com")
        XCTAssertEqual(info.socket, "/tmp/mysql.sock")
        XCTAssertEqual(info.user, "app")
        XCTAssertEqual(info.colorIndex, 3)
        XCTAssertEqual(info.port, "3307")
        XCTAssertEqual(info.database, "shop")
        XCTAssertFalse(info.useCompression)
    }

    func testConnectionTypesDecodeForAllKnownRawValues() {
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 0]).type, .tcpIP)
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 1]).type, .socket)
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 2]).type, .sshTunnel)
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 3]).type, .awsIAM)
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 4]).type, .vault)
    }

    func testUnknownConnectionTypeFallsBackToTCPIP() {
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 99]).type, .tcpIP)
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": -1]).type, .tcpIP)
    }

    // MARK: - Lenient numeric parsing (NSNumber or numeric NSString)

    func testNumericStringsDecodeLikeIntegerValue() {
        // ObjC read these via -integerValue, which NSString implements too.
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "type": "2",
            "colorIndex": "5",
            "useSSL": "1",
            "requestServerPublicKey": "1",
            "useCompression": "0"
        ])

        XCTAssertEqual(info.type, .sshTunnel)
        XCTAssertEqual(info.colorIndex, 5)
        XCTAssertEqual(info.useSSL, 1)
        XCTAssertEqual(info.requestServerPublicKey, 1)
        XCTAssertFalse(info.useCompression)
    }

    func testNumberValuesDecodeToStringFields() {
        // A numeric port survives as its string form rather than being dropped.
        let info = SAConnectionInfo.fromFavoriteDictionary(["port": NSNumber(value: 3306)])
        XCTAssertEqual(info.port, "3306")
    }

    // MARK: - Time zone

    func testServerTimeZoneModeClearsIdentifier() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "timeZoneMode": NSNumber(value: 0),
            "timeZone": "Europe/Prague"
        ])

        XCTAssertEqual(info.timeZoneMode, .useServerTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "")
    }

    func testSystemTimeZoneModeClearsIdentifier() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "timeZoneMode": NSNumber(value: 1),
            "timeZone": "Europe/Prague"
        ])

        XCTAssertEqual(info.timeZoneMode, .useSystemTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "")
    }

    func testFixedTimeZoneModeCarriesIdentifier() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "timeZoneMode": NSNumber(value: 2),
            "timeZone": "Europe/Prague"
        ])

        XCTAssertEqual(info.timeZoneMode, .useFixedTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "Europe/Prague")
    }

    func testFixedTimeZoneModeWithMissingIdentifierYieldsEmptyString() {
        let info = SAConnectionInfo.fromFavoriteDictionary(["timeZoneMode": NSNumber(value: 2)])

        XCTAssertEqual(info.timeZoneMode, .useFixedTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "")
    }

    func testUnknownTimeZoneModeFallsBackToServer() {
        let info = SAConnectionInfo.fromFavoriteDictionary(["timeZoneMode": NSNumber(value: 7)])
        XCTAssertEqual(info.timeZoneMode, .useServerTZ)
    }

    // MARK: - AWS IAM

    func testAWSIAMToggleIsDerivedFromConnectionType() {
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 3]).useAWSIAMAuth, 1)
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 0]).useAWSIAMAuth, 0)
        // A stored toggle never overrides the type-derived value.
        XCTAssertEqual(SAConnectionInfo.fromFavoriteDictionary(["type": 0, "useAWSIAMAuth": 1]).useAWSIAMAuth, 0)
    }

    func testAWSDetailsDecodeWithProfileDefault() {
        let explicit = SAConnectionInfo.fromFavoriteDictionary([
            "type": 3, "awsRegion": "eu-central-1", "awsProfile": "staging"
        ])
        XCTAssertEqual(explicit.awsRegion, "eu-central-1")
        XCTAssertEqual(explicit.awsProfile, "staging")

        let defaulted = SAConnectionInfo.fromFavoriteDictionary(["type": 3])
        XCTAssertEqual(defaulted.awsRegion, "")
        XCTAssertEqual(defaulted.awsProfile, "default")
    }

    // MARK: - Vault

    func testVaultDetailsDecode() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "type": 4,
            "vaultHost": "vault.internal",
            "vaultCredentialsPath": "database/creds/app"
        ])

        XCTAssertEqual(info.type, .vault)
        XCTAssertEqual(info.vaultHost, "vault.internal")
        XCTAssertEqual(info.vaultCredentialsPath, "database/creds/app")
        // vaultPort / vaultOIDCMount stay at their placeholders: the
        // controller applies the raw dictionary values so that a missing key
        // (nil) keeps driving the form's NSNullPlaceholder.
        XCTAssertEqual(info.vaultPort, "")
        XCTAssertEqual(info.vaultOIDCMount, "")
    }

    // MARK: - SSL / SSH

    func testSSLDetailsDecode() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "useSSL": NSNumber(value: 1),
            "sslKeyFileLocationEnabled": NSNumber(value: 1),
            "sslKeyFileLocation": "/keys/client-key.pem",
            "sslCertificateFileLocationEnabled": NSNumber(value: 1),
            "sslCertificateFileLocation": "/keys/client-cert.pem",
            "sslCACertFileLocationEnabled": NSNumber(value: 1),
            "sslCACertFileLocation": "/keys/ca.pem"
        ])

        XCTAssertEqual(info.useSSL, 1)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 1)
        XCTAssertEqual(info.sslKeyFileLocation, "/keys/client-key.pem")
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCertificateFileLocation, "/keys/client-cert.pem")
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCACertFileLocation, "/keys/ca.pem")
    }

    func testRequestServerPublicKeyDecodes() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "requestServerPublicKey": NSNumber(value: 1)
        ])

        XCTAssertEqual(info.requestServerPublicKey, 1)
    }

    func testSSHDetailsDecode() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "type": 2,
            "sshHost": "bastion.example.com",
            "sshUser": "jump",
            "sshKeyLocationEnabled": NSNumber(value: 1),
            "sshKeyLocation": "~/.ssh/id_ed25519",
            "sshPort": "2222",
            "sshRemoteSocketPath": "/var/run/mysqld/mysqld.sock"
        ])

        XCTAssertEqual(info.type, .sshTunnel)
        XCTAssertEqual(info.sshHost, "bastion.example.com")
        XCTAssertEqual(info.sshUser, "jump")
        XCTAssertEqual(info.sshKeyLocationEnabled, 1)
        XCTAssertEqual(info.sshKeyLocation, "~/.ssh/id_ed25519")
        XCTAssertEqual(info.sshPort, "2222")
        XCTAssertEqual(info.sshRemoteSocketPath, "/var/run/mysqld/mysqld.sock")
    }

    // MARK: - ObjC bridge

    func testObjCBridgeAppliesSameRules() {
        let bridged = SAConnectionInfoObjC.info(fromFavoriteDictionary: [
            "type": NSNumber(value: 3),
            "name": "IAM box",
            "colorIndex": NSNumber(value: 2)
        ] as NSDictionary)

        XCTAssertEqual(bridged.type, .awsIAM)
        XCTAssertEqual(bridged.name, "IAM box")
        XCTAssertEqual(bridged.colorIndex, 2)
        XCTAssertEqual(bridged.useAWSIAMAuth, 1)
        XCTAssertEqual(bridged.awsProfile, "default")
        XCTAssertTrue(bridged.useCompression)
    }

    func testObjCBridgeNilDictionaryYieldsDefaults() {
        let bridged = SAConnectionInfoObjC.info(fromFavoriteDictionary: nil)

        XCTAssertEqual(bridged.type, .tcpIP)
        XCTAssertEqual(bridged.colorIndex, -1)
        XCTAssertTrue(bridged.useCompression)
        XCTAssertEqual(bridged.awsProfile, "default")
    }

    // MARK: - Raw favorite string coercion (vaultPort / vaultOIDCMount)

    func testRawFavoriteStringPassesStringsThroughPreservingEmpty() {
        XCTAssertEqual(SAConnectionInfoObjC.rawFavoriteString("8200"), "8200")
        // Stored-empty stays empty — distinct from nil for the placeholder.
        XCTAssertEqual(SAConnectionInfoObjC.rawFavoriteString(""), "")
    }

    func testRawFavoriteStringCoercesNumbersFromImportedFavorites() {
        XCTAssertEqual(SAConnectionInfoObjC.rawFavoriteString(NSNumber(value: 8200)), "8200")
    }

    func testRawFavoriteStringMapsMissingAndNullToNil() {
        XCTAssertNil(SAConnectionInfoObjC.rawFavoriteString(nil))
        XCTAssertNil(SAConnectionInfoObjC.rawFavoriteString(NSNull()))
    }

    func testRawFavoriteStringRejectsNonScalarValues() {
        XCTAssertNil(SAConnectionInfoObjC.rawFavoriteString(["nested": "dict"]))
        XCTAssertNil(SAConnectionInfoObjC.rawFavoriteString([1, 2, 3]))
    }

    // MARK: - New-favorite template (Phase D2)

    func testDefaultNewFavoriteTemplateMatchesHistoricalKeySet() {
        let template = SAConnectionInfoObjC.defaultNewFavoriteDictionary(withID: NSNumber(value: 12345))

        // Exactly the 31 keys -[SPConnectionController addFavorite:] writes.
        let expectedKeys: Set<String> = [
            "name", "type", "host", "socket", "user", "colorIndex", "port",
            "timeZoneMode", "timeZone", "allowDataLocalInfile",
            "enableClearTextPlugin", "requestServerPublicKey",
            "useAWSIAMAuth", "awsRegion", "awsProfile",
            "useSSL", "sslKeyFileLocationEnabled",
            "sslCertificateFileLocationEnabled", "sslCACertFileLocationEnabled",
            "database", "sshHost", "sshUser", "sshKeyLocationEnabled",
            "sshKeyLocation", "sshPort", "sshRemoteSocketPath",
            "vaultHost", "vaultPort", "vaultOIDCMount", "vaultCredentialsPath",
            "id"
        ]
        XCTAssertEqual(Set(template.allKeys.compactMap { $0 as? String }), expectedKeys)

        // Historical quirks stay: no useCompression key, no SSL path keys.
        XCTAssertNil(template["useCompression"])
        XCTAssertNil(template["sslKeyFileLocation"])
        XCTAssertNil(template["sslCertificateFileLocation"])
        XCTAssertNil(template["sslCACertFileLocation"])
    }

    func testDefaultNewFavoriteTemplateValues() {
        let template = SAConnectionInfoObjC.defaultNewFavoriteDictionary(withID: NSNumber(value: 777))

        XCTAssertEqual(template["name"] as? String, "New Favorite")
        XCTAssertEqual((template["type"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((template["colorIndex"] as? NSNumber)?.intValue, -1)
        XCTAssertEqual((template["timeZoneMode"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((template["requestServerPublicKey"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((template["useSSL"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(template["awsProfile"] as? String, "default")
        XCTAssertEqual(template["host"] as? String, "")
        XCTAssertEqual(template["vaultPort"] as? String, "")
        XCTAssertEqual(template["vaultOIDCMount"] as? String, "")
        XCTAssertEqual((template["id"] as? NSNumber)?.intValue, 777)
    }

    func testDefaultNewFavoriteTemplateRoundTripsThroughDecoder() {
        // Decoding the template must equal decoding "no favorite" except for
        // the name — the template is the encode-side twin of the decoder.
        let template = SAConnectionInfoObjC.defaultNewFavoriteDictionary(withID: NSNumber(value: 1))
        let decoded = SAConnectionInfo.fromFavoriteDictionary(template as? [AnyHashable: Any])
        let blank = SAConnectionInfo.fromFavoriteDictionary(nil)

        XCTAssertEqual(decoded.name, "New Favorite")
        XCTAssertEqual(decoded.type, blank.type)
        XCTAssertEqual(decoded.colorIndex, blank.colorIndex)
        XCTAssertEqual(decoded.useCompression, blank.useCompression)
        XCTAssertEqual(decoded.timeZoneMode, blank.timeZoneMode)
        XCTAssertEqual(decoded.timeZoneIdentifier, blank.timeZoneIdentifier)
        XCTAssertEqual(decoded.awsProfile, blank.awsProfile)
        XCTAssertEqual(decoded.requestServerPublicKey, blank.requestServerPublicKey)
        XCTAssertEqual(decoded.useSSL, blank.useSSL)
        XCTAssertEqual(decoded.useAWSIAMAuth, blank.useAWSIAMAuth)
    }

    // MARK: - Favorite duplication (Phase D2)

    func testDuplicatedFavoriteGetsNewIDAndCopySuffix() {
        let original: NSDictionary = [
            "id": NSNumber(value: 100),
            "name": "Prod",
            "host": "db.example.com",
            "type": NSNumber(value: 2)
        ]

        let duplicate = SAConnectionInfoObjC.duplicatedFavoriteDictionary(fromFavorite: original, withID: NSNumber(value: 200))

        XCTAssertEqual((duplicate["id"] as? NSNumber)?.intValue, 200)
        XCTAssertEqual(duplicate["name"] as? String, "Prod Copy")
        // Everything else carries over untouched.
        XCTAssertEqual(duplicate["host"] as? String, "db.example.com")
        XCTAssertEqual((duplicate["type"] as? NSNumber)?.intValue, 2)
        // And the source is not mutated.
        XCTAssertEqual((original["id"] as? NSNumber)?.intValue, 100)
        XCTAssertEqual(original["name"] as? String, "Prod")
    }

    func testDuplicatedFavoriteFromNilYieldsMinimalDictionary() {
        // Defensive path: -selectedFavorite returns nil for group selections.
        let duplicate = SAConnectionInfoObjC.duplicatedFavoriteDictionary(fromFavorite: nil, withID: NSNumber(value: 5))

        XCTAssertEqual((duplicate["id"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual(duplicate["name"] as? String, " Copy")
        XCTAssertEqual(duplicate.count, 2)
    }
}
