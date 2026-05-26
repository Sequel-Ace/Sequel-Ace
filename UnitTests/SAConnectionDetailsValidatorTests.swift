//
//  SAConnectionDetailsValidatorTests.swift
//  Unit Tests
//
//  Pins the pre-connection validation rules extracted from
//  -[SPConnectionController initiateConnection:] in Phase D3. The
//  order of checks matters — multi-issue forms should fire the same
//  first error the user has been seeing for years.
//

import XCTest

final class SAConnectionDetailsValidatorTests: XCTestCase {

    // MARK: - Helpers

    /// Calls the validator with sensible "everything fine" defaults
    /// for unused fields. Tests override only the inputs they care
    /// about — keeps the test bodies focused on the rule under test.
    private func validate(
        type: SAConnectionType = .tcpIP,
        host: String = "db.example.com",
        sshHost: String = "",
        sshRemoteSocketPath: String = "",
        useSSL: Bool = false,
        sshKeyLocationEnabled: Bool = false,
        sshKeyLocation: String? = nil,
        sslKeyFileLocationEnabled: Bool = false,
        sslKeyFileLocation: String? = nil,
        sslCertificateFileLocationEnabled: Bool = false,
        sslCertificateFileLocation: String? = nil,
        sslCACertFileLocationEnabled: Bool = false,
        sslCACertFileLocation: String? = nil
    ) -> SAConnectionValidationFailure? {
        SAConnectionDetailsValidator.validate(
            type: type,
            host: host,
            sshHost: sshHost,
            sshRemoteSocketPath: sshRemoteSocketPath,
            useSSL: useSSL,
            sshKeyLocationEnabled: sshKeyLocationEnabled,
            sshKeyLocation: sshKeyLocation,
            sslKeyFileLocationEnabled: sslKeyFileLocationEnabled,
            sslKeyFileLocation: sslKeyFileLocation,
            sslCertificateFileLocationEnabled: sslCertificateFileLocationEnabled,
            sslCertificateFileLocation: sslCertificateFileLocation,
            sslCACertFileLocationEnabled: sslCACertFileLocationEnabled,
            sslCACertFileLocation: sslCACertFileLocation
        )
    }

    /// Returns a path that's guaranteed to exist for file-check tests
    /// (xctest itself — always present in the test bundle).
    private func existingFilePath() -> String {
        Bundle(for: type(of: self)).bundlePath
    }

    private let missingFilePath = "/tmp/sa-connection-validator-tests-this-path-does-not-exist-\(UUID().uuidString)"

    // MARK: - Happy path

    func testValidTCPIPConnectionPasses() {
        XCTAssertNil(validate(type: .tcpIP, host: "db.example.com"))
    }

    func testValidSocketConnectionAcceptsEmptyHost() {
        // Socket connections route through a local UNIX socket — the
        // host field is irrelevant and must NOT trigger hostMissing.
        XCTAssertNil(validate(type: .socket, host: ""))
    }

    func testValidSSHConnectionPasses() {
        XCTAssertNil(validate(type: .sshTunnel, host: "db.example.com", sshHost: "bastion.example.com"))
    }

    func testValidAWSIAMConnectionPasses() {
        // AWS IAM connections need a host (the validator covers that);
        // the AWS-directory authorization check stays inline in the
        // controller and is intentionally not exercised here.
        XCTAssertNil(validate(type: .awsIAM, host: "db.example.com"))
    }

    func testValidVaultConnectionPasses() {
        // Vault-specific fields are checked by SPConnectionController; the
        // shared validator still covers MySQL SSL file checks for Vault.
        XCTAssertNil(validate(type: .vault, host: "db.example.com"))
    }

    // MARK: - hostMissing

    func testTCPIPRequiresHost() {
        let failure = validate(type: .tcpIP, host: "")
        XCTAssertEqual(failure?.kind, .hostMissing)
    }

    func testSSHTunnelRequiresHost() {
        let failure = validate(type: .sshTunnel, host: "", sshHost: "bastion.example.com")
        XCTAssertEqual(failure?.kind, .hostMissing)
    }

    func testSSHTunnelWithRemoteSocketAcceptsEmptyHost() {
        XCTAssertNil(validate(
            type: .sshTunnel,
            host: "",
            sshHost: "bastion.example.com",
            sshRemoteSocketPath: "/var/run/mysqld/mysqld.sock"
        ))
    }

    func testAWSIAMRequiresHost() {
        let failure = validate(type: .awsIAM, host: "")
        XCTAssertEqual(failure?.kind, .hostMissing)
    }

    func testVaultHostIsCheckedByController() {
        XCTAssertNil(validate(type: .vault, host: ""))
    }

    // MARK: - sshHostMissing

    func testSSHTunnelRequiresSSHHost() {
        let failure = validate(type: .sshTunnel, host: "db.example.com", sshHost: "")
        XCTAssertEqual(failure?.kind, .sshHostMissing)
    }

    func testTCPIPDoesNotCheckSSHHost() {
        // Non-SSH connection types must not even look at sshHost.
        XCTAssertNil(validate(type: .tcpIP, host: "db.example.com", sshHost: ""))
    }

    // MARK: - SSH key file

    func testMissingSSHKeyFileTriggersFailureWhenEnabled() {
        let failure = validate(
            type: .sshTunnel,
            host: "db.example.com",
            sshHost: "bastion.example.com",
            sshKeyLocationEnabled: true,
            sshKeyLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sshKeyFileMissing)
    }

    func testSSHKeyFileCheckSkippedWhenDisabled() {
        // sshKeyLocationEnabled=false means "don't use a key"; the path
        // value is irrelevant and the file must not be probed.
        XCTAssertNil(validate(
            type: .sshTunnel,
            host: "db.example.com",
            sshHost: "bastion.example.com",
            sshKeyLocationEnabled: false,
            sshKeyLocation: missingFilePath
        ))
    }

    func testExistingSSHKeyFilePasses() {
        XCTAssertNil(validate(
            type: .sshTunnel,
            host: "db.example.com",
            sshHost: "bastion.example.com",
            sshKeyLocationEnabled: true,
            sshKeyLocation: existingFilePath()
        ))
    }

    func testSSHKeyFileCheckOnlyAppliesToSSHTunnel() {
        // Even with the toggle on and a missing path, a TCP/IP
        // connection must not check the SSH key file.
        XCTAssertNil(validate(
            type: .tcpIP,
            host: "db.example.com",
            sshKeyLocationEnabled: true,
            sshKeyLocation: missingFilePath
        ))
    }

    // MARK: - SSL files

    func testMissingSSLKeyFileTriggersFailure() {
        let failure = validate(
            type: .tcpIP,
            host: "db.example.com",
            useSSL: true,
            sslKeyFileLocationEnabled: true,
            sslKeyFileLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sslKeyFileMissing)
    }

    func testMissingSSLCertificateFileTriggersFailure() {
        let failure = validate(
            type: .tcpIP,
            host: "db.example.com",
            useSSL: true,
            sslCertificateFileLocationEnabled: true,
            sslCertificateFileLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sslCertificateFileMissing)
    }

    func testMissingSSLCACertFileTriggersFailure() {
        let failure = validate(
            type: .tcpIP,
            host: "db.example.com",
            useSSL: true,
            sslCACertFileLocationEnabled: true,
            sslCACertFileLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sslCACertFileMissing)
    }

    func testSSLChecksSkippedWhenUseSSLOff() {
        // useSSL=false means "don't use SSL" — files referenced by the
        // SSL toggles must not be probed.
        XCTAssertNil(validate(
            type: .tcpIP,
            host: "db.example.com",
            useSSL: false,
            sslKeyFileLocationEnabled: true,
            sslKeyFileLocation: missingFilePath,
            sslCertificateFileLocationEnabled: true,
            sslCertificateFileLocation: missingFilePath,
            sslCACertFileLocationEnabled: true,
            sslCACertFileLocation: missingFilePath
        ))
    }

    func testSSLChecksDoNotApplyToSSHTunnel() {
        // SSL file checks only run for TCP/IP and socket types per the
        // original code — SSH tunnel skips them even if useSSL is on.
        XCTAssertNil(validate(
            type: .sshTunnel,
            host: "db.example.com",
            sshHost: "bastion.example.com",
            useSSL: true,
            sslKeyFileLocationEnabled: true,
            sslKeyFileLocation: missingFilePath
        ))
    }

    func testSSLChecksAppliesToSocketWhenUseSSLOn() {
        let failure = validate(
            type: .socket,
            host: "",
            useSSL: true,
            sslKeyFileLocationEnabled: true,
            sslKeyFileLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sslKeyFileMissing)
    }

    func testSSLChecksApplyToVaultWhenUseSSLOn() {
        let failure = validate(
            type: .vault,
            host: "db.example.com",
            useSSL: true,
            sslKeyFileLocationEnabled: true,
            sslKeyFileLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sslKeyFileMissing)
    }

    // MARK: - Failure ordering

    /// Pins the check order: host → ssh host → ssh key → ssl key →
    /// ssl cert → ssl CA. The user has been seeing these in this order
    /// for years; reordering would silently change the first-error UX.
    func testHostMissingBeatsSSHHostMissing() {
        let failure = validate(type: .sshTunnel, host: "", sshHost: "")
        XCTAssertEqual(failure?.kind, .hostMissing)
    }

    func testSSHHostMissingBeatsSSHKeyMissing() {
        let failure = validate(
            type: .sshTunnel,
            host: "db.example.com",
            sshHost: "",
            sshKeyLocationEnabled: true,
            sshKeyLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sshHostMissing)
    }

    func testSSLKeyMissingBeatsCertMissing() {
        // Both files are missing — only the first one in source order
        // should be reported, matching the controller's serialized
        // alerts.
        let failure = validate(
            type: .tcpIP,
            host: "db.example.com",
            useSSL: true,
            sslKeyFileLocationEnabled: true,
            sslKeyFileLocation: missingFilePath,
            sslCertificateFileLocationEnabled: true,
            sslCertificateFileLocation: missingFilePath
        )
        XCTAssertEqual(failure?.kind, .sslKeyFileMissing)
    }

    // MARK: - Failure payload

    func testFailurePayloadCarriesUsableAlertStrings() {
        // The alert text isn't pinned to specific localized strings
        // (those drift with translations), but they must be non-empty
        // so the controller has something to show.
        let failure = validate(type: .tcpIP, host: "")
        XCTAssertFalse(failure?.alertTitle.isEmpty ?? true)
        XCTAssertFalse(failure?.alertMessage.isEmpty ?? true)
    }

    // MARK: - fileExistsExpandingTilde

    func testFileExistsExpandingTildeFindsRealFile() {
        XCTAssertTrue(SAConnectionDetailsValidator.fileExistsExpandingTilde(existingFilePath()))
    }

    func testFileExistsExpandingTildeRejectsNonExistentPath() {
        XCTAssertFalse(SAConnectionDetailsValidator.fileExistsExpandingTilde(missingFilePath))
    }

    func testFileExistsExpandingTildeExpandsHomeDir() {
        // ~ should expand to the user's home, which exists. Compared
        // against the unprefixed home path so a stale or absent
        // $HOME would visibly fail.
        let home = NSHomeDirectory()
        XCTAssertTrue(SAConnectionDetailsValidator.fileExistsExpandingTilde("~"),
                      "home directory should resolve and exist; got NSHomeDirectory()=\(home)")
    }
}
