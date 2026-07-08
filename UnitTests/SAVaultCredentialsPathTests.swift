//  SAVaultCredentialsPathTests.swift
//  Sequel Ace

import XCTest

final class SAVaultCredentialsPathTests: XCTestCase {

    func testMountIsPrefixBeforeCreds() {
        XCTAssertEqual(SAVaultCredentialsPath.mount(fromCredPath: "databases_credentials/creds/role-name"),
                       "databases_credentials")
    }

    func testRoleIsSuffixAfterCreds() {
        XCTAssertEqual(SAVaultCredentialsPath.role(fromCredPath: "databases_credentials/creds/role-name"),
                       "role-name")
    }

    func testNestedMountIsPreserved() {
        XCTAssertEqual(SAVaultCredentialsPath.mount(fromCredPath: "team/db/creds/ro"), "team/db")
        XCTAssertEqual(SAVaultCredentialsPath.role(fromCredPath: "team/db/creds/ro"), "ro")
    }

    func testMountContainingCredsSegmentIsPreserved() {
        // A valid nested mount whose path itself contains a `creds` segment must
        // split at the final separator, not the first one.
        let path = "team/creds/mysql/creds/readonly"
        XCTAssertEqual(SAVaultCredentialsPath.mount(fromCredPath: path), "team/creds/mysql")
        XCTAssertEqual(SAVaultCredentialsPath.role(fromCredPath: path), "readonly")
        let rebuilt = SAVaultCredentialsPath.credPath(
            mount: SAVaultCredentialsPath.mount(fromCredPath: path),
            role: SAVaultCredentialsPath.role(fromCredPath: path))
        XCTAssertEqual(rebuilt, path)
    }

    func testPathWithoutCredsFallsBackToRole() {
        // Unparseable path: keep the whole string as the role so nothing is lost.
        XCTAssertEqual(SAVaultCredentialsPath.mount(fromCredPath: "weird-value"), "")
        XCTAssertEqual(SAVaultCredentialsPath.role(fromCredPath: "weird-value"), "weird-value")
    }

    func testCredPathJoinsMountAndRole() {
        XCTAssertEqual(SAVaultCredentialsPath.credPath(mount: "databases_credentials", role: "role-name"),
                       "databases_credentials/creds/role-name")
    }

    func testCredPathTrimsWhitespaceAndSlashes() {
        XCTAssertEqual(SAVaultCredentialsPath.credPath(mount: " databases_credentials/ ", role: " /role-name "),
                       "databases_credentials/creds/role-name")
    }

    func testCredPathWithEmptyMountReturnsRoleVerbatim() {
        // Lets a user paste a full path into the role field with no mount.
        XCTAssertEqual(SAVaultCredentialsPath.credPath(mount: "", role: "databases_credentials/creds/x"),
                       "databases_credentials/creds/x")
    }

    func testCredPathWithEmptyRoleIsEmpty() {
        XCTAssertEqual(SAVaultCredentialsPath.credPath(mount: "databases_credentials", role: "  "), "")
    }

    func testCredPathHonorsFullPathPastedIntoRoleWhenMountIsSet() {
        // Pasting a full path into Role while the mount is populated must not
        // double the path (regression: databases_credentials/creds/databases_credentials/creds/RW).
        XCTAssertEqual(
            SAVaultCredentialsPath.credPath(mount: "databases_credentials",
                                            role: "databases_credentials/creds/RW"),
            "databases_credentials/creds/RW")
    }

    func testCredPathHonorsFullPathWithDifferentMountPastedIntoRole() {
        // The pasted path wins over the mount field entirely.
        XCTAssertEqual(
            SAVaultCredentialsPath.credPath(mount: "some_mount", role: "other_mount/creds/ro"),
            "other_mount/creds/ro")
    }

    func testRoundTrip() {
        let original = "databases_credentials/creds/role-name"
        let rebuilt = SAVaultCredentialsPath.credPath(
            mount: SAVaultCredentialsPath.mount(fromCredPath: original),
            role: SAVaultCredentialsPath.role(fromCredPath: original))
        XCTAssertEqual(rebuilt, original)
    }
}
