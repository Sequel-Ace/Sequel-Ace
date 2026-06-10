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
            "password": "secret", "sshPassword": "tunnel-secret",
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
            "useCompression": NSNumber(value: false),
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
            "useCompression": "0",
        ])

        XCTAssertEqual(info.type, .sshTunnel)
        XCTAssertEqual(info.colorIndex, 5)
        XCTAssertEqual(info.useSSL, 1)
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
            "timeZone": "Europe/Prague",
        ])

        XCTAssertEqual(info.timeZoneMode, .useServerTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "")
    }

    func testSystemTimeZoneModeClearsIdentifier() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "timeZoneMode": NSNumber(value: 1),
            "timeZone": "Europe/Prague",
        ])

        XCTAssertEqual(info.timeZoneMode, .useSystemTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "")
    }

    func testFixedTimeZoneModeCarriesIdentifier() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "timeZoneMode": NSNumber(value: 2),
            "timeZone": "Europe/Prague",
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
            "type": 3, "awsRegion": "eu-central-1", "awsProfile": "staging",
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
            "vaultCredentialsPath": "database/creds/app",
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
            "sslCACertFileLocation": "/keys/ca.pem",
        ])

        XCTAssertEqual(info.useSSL, 1)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 1)
        XCTAssertEqual(info.sslKeyFileLocation, "/keys/client-key.pem")
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCertificateFileLocation, "/keys/client-cert.pem")
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCACertFileLocation, "/keys/ca.pem")
    }

    func testSSHDetailsDecode() {
        let info = SAConnectionInfo.fromFavoriteDictionary([
            "type": 2,
            "sshHost": "bastion.example.com",
            "sshUser": "jump",
            "sshKeyLocationEnabled": NSNumber(value: 1),
            "sshKeyLocation": "~/.ssh/id_ed25519",
            "sshPort": "2222",
            "sshRemoteSocketPath": "/var/run/mysqld/mysqld.sock",
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
            "colorIndex": NSNumber(value: 2),
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
}
