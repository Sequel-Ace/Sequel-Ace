//
//  SAFavoriteDuplicateMatcherTests.swift
//  Unit Tests
//
//  Pins the duplicate-detection rules extracted from SPConnectionController
//  (modernization item 4). These rules decide which imported connections are
//  flagged as duplicates of existing favorites, so their exact shape — the
//  Vault-compares-as-TCP/IP quirk included — is wire-format-adjacent behaviour.
//

import XCTest

final class SAFavoriteDuplicateMatcherTests: XCTestCase {

    // MARK: - Type mapping

    func testKnownTypeStringsRoundTrip() {
        for (tag, string) in [(1, "SPSocketConnection"), (2, "SPSSHTunnelConnection"), (3, "SPAWSIAMConnection"), (0, "SPTCPIPConnection")] {
            XCTAssertEqual(SAFavoriteDuplicateMatcher.typeTag(forString: string), tag)
            XCTAssertEqual(SAFavoriteDuplicateMatcher.typeString(forTag: tag), string)
        }
    }

    func testUnknownTypeStringsDefaultToTCPIP() {
        XCTAssertEqual(SAFavoriteDuplicateMatcher.typeTag(forString: "nonsense"), 0)
        XCTAssertEqual(SAFavoriteDuplicateMatcher.typeTag(forString: nil), 0)
    }

    /// The deliberate quirk: Vault (tag 4) has no string of its own, so it maps
    /// through the TCP/IP default in both directions and compares as TCP/IP for
    /// duplicate purposes. Changing this changes which imports are flagged.
    func testVaultFallsThroughToTCPIP() {
        XCTAssertEqual(SAFavoriteDuplicateMatcher.typeString(forTag: 4), "SPTCPIPConnection")
    }

    // MARK: - Port normalization

    func testNumberAndStringPortsCompareEqual() {
        XCTAssertEqual(SAFavoriteDuplicateMatcher.normalizedPort(NSNumber(value: 3307), typeString: "SPTCPIPConnection"),
                       SAFavoriteDuplicateMatcher.normalizedPort(" 3307 ", typeString: "SPTCPIPConnection"))
    }

    func testAnEmptyPortMeansTheMySQLDefault() {
        XCTAssertEqual(SAFavoriteDuplicateMatcher.normalizedPort("", typeString: "SPTCPIPConnection"), "3306")
        XCTAssertEqual(SAFavoriteDuplicateMatcher.normalizedPort(nil, typeString: "SPSSHTunnelConnection"), "3306")
    }

    /// The port is irrelevant to socket connections, so an empty one stays
    /// empty rather than becoming 3306.
    func testSocketConnectionsKeepAnEmptyPortEmpty() {
        XCTAssertEqual(SAFavoriteDuplicateMatcher.normalizedPort("", typeString: "SPSocketConnection"), "")
        XCTAssertEqual(SAFavoriteDuplicateMatcher.normalizedPort("3307", typeString: "SPSocketConnection"), "3307")
    }

    // MARK: - The base predicate

    private let existingTCPIP: NSDictionary = [
        "host": "db.example.com", "user": "app", "database": "sakila",
        "port": "3306", "type": 0,
    ]

    private func isDuplicate(_ existing: NSDictionary,
                             host: String = "db.example.com",
                             user: String = "app",
                             database: String = "sakila",
                             port: String = "3306",
                             type: String = "SPTCPIPConnection",
                             modeFields: NSDictionary? = nil) -> Bool {
        SAFavoriteDuplicateMatcher.favorite(existing,
                                            isDuplicateOfHost: host, user: user,
                                            database: database, port: port,
                                            typeString: type,
                                            modeSpecificFields: modeFields)
    }

    func testIdenticalDetailsMatch() {
        XCTAssertTrue(isDuplicate(existingTCPIP))
    }

    func testEachBaseFieldDiscriminates() {
        XCTAssertFalse(isDuplicate(existingTCPIP, host: "other.example.com"))
        XCTAssertFalse(isDuplicate(existingTCPIP, user: "someone"))
        XCTAssertFalse(isDuplicate(existingTCPIP, database: "world"))
        XCTAssertFalse(isDuplicate(existingTCPIP, port: "3307"))
        XCTAssertFalse(isDuplicate(existingTCPIP, type: "SPSocketConnection"))
    }

    /// An empty candidate port and an explicit 3306 are the same connection.
    func testDefaultPortSpellingsMatch() {
        XCTAssertTrue(isDuplicate(existingTCPIP, port: ""))
    }

    /// Favorites store the port as NSNumber or NSString; both must match.
    func testNumberStoredPortMatchesStringCandidate() {
        let existing: NSDictionary = [
            "host": "db.example.com", "user": "app", "database": "sakila",
            "port": NSNumber(value: 3306), "type": 0,
        ]
        XCTAssertTrue(isDuplicate(existing))
    }

    /// The stored type may be a numeric string (plist round-trips).
    func testStringStoredTypeIsReadLeniently() {
        let existing: NSDictionary = [
            "host": "db.example.com", "user": "app", "database": "sakila",
            "port": "3306", "type": "0",
        ]
        XCTAssertTrue(isDuplicate(existing))
    }

    /// Absent fields read as "" — an import candidate with empty user matches a
    /// favorite that never stored one.
    func testAbsentFieldsReadAsEmpty() {
        let existing: NSDictionary = ["host": "db.example.com", "type": 0]
        XCTAssertTrue(isDuplicate(existing, user: "", database: "", port: ""))
    }

    // MARK: - Mode-specific comparison

    private let existingSSH: NSDictionary = [
        "host": "db.internal", "user": "app", "database": "", "port": "3306", "type": 2,
        "sshHost": "bastion.example.com", "sshUser": "jump", "sshPort": "22", "sshRemoteSocketPath": "",
    ]

    func testSSHFieldsCompareWhenModeFieldsSupplied() {
        let matching: NSDictionary = ["ssh_host": "bastion.example.com", "ssh_user": "jump", "ssh_port": "22", "ssh_remote_socket_path": ""]
        XCTAssertTrue(isDuplicate(existingSSH, host: "db.internal", database: "", type: "SPSSHTunnelConnection", modeFields: matching))

        let differing: NSDictionary = ["ssh_host": "other-bastion", "ssh_user": "jump", "ssh_port": "22", "ssh_remote_socket_path": ""]
        XCTAssertFalse(isDuplicate(existingSSH, host: "db.internal", database: "", type: "SPSSHTunnelConnection", modeFields: differing))
    }

    /// Both import paths funnel here: connection-string imports use URL keys,
    /// plist imports use favorite keys. The favorite-key spelling must match too.
    func testModeFieldsAreReadUnderFavoriteKeysToo() {
        let plistShaped: NSDictionary = ["sshHost": "bastion.example.com", "sshUser": "jump", "sshPort": "22", "sshRemoteSocketPath": ""]
        XCTAssertTrue(isDuplicate(existingSSH, host: "db.internal", database: "", type: "SPSSHTunnelConnection", modeFields: plistShaped))
    }

    /// The URL key wins when both spellings are present.
    func testURLKeyTakesPrecedenceOverFavoriteKey() {
        let both: NSDictionary = ["ssh_host": "other-bastion", "sshHost": "bastion.example.com",
                                  "ssh_user": "jump", "ssh_port": "22", "ssh_remote_socket_path": ""]
        XCTAssertFalse(isDuplicate(existingSSH, host: "db.internal", database: "", type: "SPSSHTunnelConnection", modeFields: both))
    }

    func testSocketPathCompares() {
        let existing: NSDictionary = ["host": "", "user": "app", "database": "", "port": "", "type": 1,
                                      "socket": "/tmp/mysql.sock"]
        XCTAssertTrue(isDuplicate(existing, host: "", database: "", port: "", type: "SPSocketConnection",
                                  modeFields: ["socket": "/tmp/mysql.sock"]))
        XCTAssertFalse(isDuplicate(existing, host: "", database: "", port: "", type: "SPSocketConnection",
                                   modeFields: ["socket": "/var/run/mysqld/mysqld.sock"]))
    }

    func testAWSRegionAndProfileCompare() {
        let existing: NSDictionary = ["host": "db.rds.amazonaws.com", "user": "app", "database": "", "port": "3306", "type": 3,
                                      "awsRegion": "eu-west-1", "awsProfile": "default"]
        XCTAssertTrue(isDuplicate(existing, host: "db.rds.amazonaws.com", database: "", type: "SPAWSIAMConnection",
                                  modeFields: ["aws_region": "eu-west-1", "aws_profile": "default"]))
        XCTAssertFalse(isDuplicate(existing, host: "db.rds.amazonaws.com", database: "", type: "SPAWSIAMConnection",
                                   modeFields: ["aws_region": "us-east-1", "aws_profile": "default"]))
    }

    /// nil modeFields skips the per-type comparison entirely — the URL-import
    /// path calls it that way after matching those fields itself.
    func testNilModeFieldsSkipsPerTypeComparison() {
        XCTAssertTrue(isDuplicate(existingSSH, host: "db.internal", database: "", type: "SPSSHTunnelConnection", modeFields: nil))
    }

    /// TCP/IP has no per-type fields, so supplying modeFields changes nothing.
    func testTCPIPIgnoresModeFields() {
        XCTAssertTrue(isDuplicate(existingTCPIP, modeFields: ["anything": "at all"]))
    }

    // MARK: - Applying an update

    func testMergeAppliesEveryFieldButNameAndID() {
        let existing: NSDictionary = ["id": 42, "name": "My Prod", "host": "old.example.com",
                                      "user": "app", "port": "3306"]
        let incoming: NSDictionary = ["id": 999, "name": "Imported", "host": "new.example.com",
                                      "database": "sakila"]

        let merged = SAFavoriteDuplicateMatcher.mergedFavorite(from: existing, applying: incoming)

        XCTAssertEqual(merged["id"] as? Int, 42, "identity stays with the favorite being updated")
        XCTAssertEqual(merged["name"] as? String, "My Prod", "the user-chosen name survives")
        XCTAssertEqual(merged["host"] as? String, "new.example.com")
        XCTAssertEqual(merged["database"] as? String, "sakila")
        XCTAssertEqual(merged["user"] as? String, "app", "fields absent from the import are kept")
    }

    func testMergeDoesNotMutateTheInputs() {
        let existing: NSDictionary = ["id": 1, "name": "A", "host": "old"]
        let incoming: NSDictionary = ["host": "new"]

        _ = SAFavoriteDuplicateMatcher.mergedFavorite(from: existing, applying: incoming)

        XCTAssertEqual(existing["host"] as? String, "old")
        XCTAssertEqual(incoming.count, 1)
    }
}
