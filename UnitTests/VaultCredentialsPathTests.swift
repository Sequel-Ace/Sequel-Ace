//  VaultCredentialsPathTests.swift
//  Sequel Ace

import XCTest

final class VaultCredentialsPathTests: XCTestCase {

    func testMountIsPrefixBeforeCreds() {
        XCTAssertEqual(VaultCredentialsPath.mount(fromCredPath: "databases_credentials/creds/role-name"),
                       "databases_credentials")
    }

    func testRoleIsSuffixAfterCreds() {
        XCTAssertEqual(VaultCredentialsPath.role(fromCredPath: "databases_credentials/creds/role-name"),
                       "role-name")
    }

    func testNestedMountIsPreserved() {
        XCTAssertEqual(VaultCredentialsPath.mount(fromCredPath: "team/db/creds/ro"), "team/db")
        XCTAssertEqual(VaultCredentialsPath.role(fromCredPath: "team/db/creds/ro"), "ro")
    }

    func testPathWithoutCredsFallsBackToRole() {
        // Unparseable path: keep the whole string as the role so nothing is lost.
        XCTAssertEqual(VaultCredentialsPath.mount(fromCredPath: "weird-value"), "")
        XCTAssertEqual(VaultCredentialsPath.role(fromCredPath: "weird-value"), "weird-value")
    }

    func testCredPathJoinsMountAndRole() {
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: "databases_credentials", role: "role-name"),
                       "databases_credentials/creds/role-name")
    }

    func testCredPathTrimsWhitespaceAndSlashes() {
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: " databases_credentials/ ", role: " /role-name "),
                       "databases_credentials/creds/role-name")
    }

    func testCredPathWithEmptyMountReturnsRoleVerbatim() {
        // Lets a user paste a full path into the role field with no mount.
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: "", role: "databases_credentials/creds/x"),
                       "databases_credentials/creds/x")
    }

    func testCredPathWithEmptyRoleIsEmpty() {
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: "databases_credentials", role: "  "), "")
    }

    func testRoundTrip() {
        let original = "databases_credentials/creds/role-name"
        let rebuilt = VaultCredentialsPath.credPath(
            mount: VaultCredentialsPath.mount(fromCredPath: original),
            role: VaultCredentialsPath.role(fromCredPath: original))
        XCTAssertEqual(rebuilt, original)
    }
}
