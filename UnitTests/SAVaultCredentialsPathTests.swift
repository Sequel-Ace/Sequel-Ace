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

    func testRoundTrip() {
        let original = "databases_credentials/creds/role-name"
        let rebuilt = SAVaultCredentialsPath.credPath(
            mount: SAVaultCredentialsPath.mount(fromCredPath: original),
            role: SAVaultCredentialsPath.role(fromCredPath: original))
        XCTAssertEqual(rebuilt, original)
    }
}
