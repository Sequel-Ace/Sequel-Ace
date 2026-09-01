//
//  SAConnectionServiceTests.swift
//  Unit Tests
//
//  Tests for the connection service's pure Swift support types and
//  connection info → service parameter mapping.
//  SAConnectionResult and SAConnectionPreferences live in the app target
//  (depend on SPMySQL), so they're tested via integration, not here.
//

import XCTest
import SPMySQL

// MARK: - SSH Tunnel Failure Tests

final class SASSHTunnelFailureTests: XCTestCase {

    func testSSHFailurePreservesTunnelDiagnostics() {
        let debugMessages = """
        debug1: Connecting to jump.local [192.168.1.8] port 22.
        ssh: connect to host jump.local port 22: No route to host
        """

        let failure = SASSHTunnelFailure(
            message: "The SSH Tunnel has unexpectedly closed.",
            debugMessages: debugMessages
        )

        XCTAssertEqual(failure.message, "The SSH Tunnel has unexpectedly closed.")
        XCTAssertEqual(failure.errorDetail, debugMessages)
        XCTAssertEqual(failure.debugMessages, debugMessages)
    }

    func testSSHFailureOmitsEmptyTunnelDiagnosticsFromDetail() {
        let failure = SASSHTunnelFailure(message: "Failed to create SSH tunnel", debugMessages: "")

        XCTAssertNil(failure.errorDetail)
        XCTAssertEqual(failure.debugMessages, "")
    }
}

final class SASSHStderrDrainCoordinatorTests: XCTestCase {

    func testAttemptLifecycleControlsDiagnosticsReadiness() {
        let coordinator = SASSHStderrDrainCoordinator()

        XCTAssertTrue(coordinator.failureDiagnosticsReady)

        XCTAssertEqual(coordinator.requestAttempt(), .start)
        XCTAssertFalse(coordinator.failureDiagnosticsReady)
        XCTAssertEqual(coordinator.requestAttempt(), .ignored)

        coordinator.finishWithoutStandardErrorPipe()
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
        XCTAssertEqual(coordinator.requestAttempt(), .start)
    }

    func testStandardErrorReadsRearmUntilEOF() {
        let coordinator = SASSHStderrDrainCoordinator(timeout: 1)
        XCTAssertEqual(coordinator.requestAttempt(), .start)
        coordinator.beginStandardErrorDrain()

        XCTAssertTrue(coordinator.recordStandardErrorRead(byteCount: 128))
        XCTAssertFalse(coordinator.failureDiagnosticsReady)
        XCTAssertFalse(coordinator.recordStandardErrorRead(byteCount: 0))

        XCTAssertTrue(coordinator.finishAfterStandardErrorDrain())
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
        XCTAssertFalse(coordinator.completeDrainNotificationAndReservePendingAttempt())
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
    }

    func testDrainTimeoutStillMakesDiagnosticsReady() {
        let coordinator = SASSHStderrDrainCoordinator(timeout: 0)
        XCTAssertEqual(coordinator.requestAttempt(), .start)
        coordinator.beginStandardErrorDrain()

        XCTAssertFalse(coordinator.finishAfterStandardErrorDrain())
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
        XCTAssertFalse(coordinator.completeDrainNotificationAndReservePendingAttempt())
    }

    func testAttemptRequestedDuringDrainIsReservedAndCoalesced() {
        let coordinator = SASSHStderrDrainCoordinator(timeout: 0)
        XCTAssertEqual(coordinator.requestAttempt(), .start)
        coordinator.beginStandardErrorDrain()

        XCTAssertEqual(coordinator.requestAttempt(), .queued)
        XCTAssertEqual(coordinator.requestAttempt(), .queued)
        XCTAssertTrue(coordinator.connectionAttemptPending)

        XCTAssertFalse(coordinator.finishAfterStandardErrorDrain())
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
        XCTAssertEqual(coordinator.requestAttempt(), .queued)
        XCTAssertTrue(coordinator.connectionAttemptPending)

        XCTAssertTrue(coordinator.completeDrainNotificationAndReservePendingAttempt())
        XCTAssertFalse(coordinator.connectionAttemptPending)
        XCTAssertFalse(coordinator.failureDiagnosticsReady)
        XCTAssertEqual(coordinator.requestAttempt(), .ignored)

        coordinator.finishWithoutStandardErrorPipe()
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
    }

    func testQueuedAttemptCanBeCancelledBeforeReservation() {
        let coordinator = SASSHStderrDrainCoordinator(timeout: 0)
        XCTAssertEqual(coordinator.requestAttempt(), .start)
        coordinator.beginStandardErrorDrain()
        XCTAssertEqual(coordinator.requestAttempt(), .queued)

        XCTAssertTrue(coordinator.cancelPendingOrRunningAttempt())
        XCTAssertFalse(coordinator.connectionAttemptPending)
        XCTAssertTrue(coordinator.attemptCancellationRequested)
        XCTAssertEqual(coordinator.requestAttempt(), .ignored)
        XCTAssertFalse(coordinator.finishAfterStandardErrorDrain())
        XCTAssertFalse(coordinator.completeDrainNotificationAndReservePendingAttempt())
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
    }

    func testReservedAttemptCancellationIsObservedBeforeLaunch() {
        let coordinator = SASSHStderrDrainCoordinator(timeout: 0)
        XCTAssertEqual(coordinator.requestAttempt(), .start)
        coordinator.beginStandardErrorDrain()
        XCTAssertEqual(coordinator.requestAttempt(), .queued)
        XCTAssertFalse(coordinator.finishAfterStandardErrorDrain())
        XCTAssertTrue(coordinator.completeDrainNotificationAndReservePendingAttempt())

        XCTAssertTrue(coordinator.cancelPendingOrRunningAttempt())
        XCTAssertTrue(coordinator.attemptCancellationRequested)

        coordinator.finishWithoutStandardErrorPipe()
        XCTAssertFalse(coordinator.attemptCancellationRequested)
        XCTAssertTrue(coordinator.failureDiagnosticsReady)
    }
}

private final class SAConnectionProxyDisconnectSpy: NSObject, SPMySQLConnectionProxy {
    private(set) var disconnectCallCount = 0

    func connect() {}

    func disconnect() {
        disconnectCallCount += 1
    }

    func state() -> SPMySQLConnectionProxyState {
        SPMySQLProxyIdle
    }

    func localPort() -> UInt {
        0
    }

    func setConnectionStateChange(_ selector: Selector!, delegate: Any!) -> Bool {
        true
    }
}

final class SAConnectionProxyDisconnectTests: XCTestCase {

    func testDisconnectReachesProxyWhenMySQLConnectionIsAlreadyInactive() {
        let connection = SPMySQLConnection()
        let proxy = SAConnectionProxyDisconnectSpy()
        connection.setProxy(proxy)

        connection.disconnect()

        XCTAssertEqual(proxy.disconnectCallCount, 1)
    }
}

// MARK: - Connection Info Parameter Mapping Tests

/// Tests connection parameter storage and the pure Swift mappings that
/// SAConnectionService consumes.
final class SAConnectionInfoMappingTests: XCTestCase {

    func testTCPIPInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .tcpIP
        info.host = "db.example.com"
        info.port = "3306"
        info.user = "admin"
        info.password = "secret"
        info.database = "mydb"

        XCTAssertEqual(info.type, .tcpIP)
        XCTAssertEqual(info.host, "db.example.com")
        XCTAssertEqual(info.port, "3306")
        XCTAssertEqual(info.user, "admin")
        XCTAssertEqual(info.password, "secret")
        XCTAssertEqual(info.database, "mydb")
        XCTAssertEqual(info.socket, "")
    }

    func testSocketInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .socket
        info.socket = "/tmp/mysql.sock"
        info.user = "root"

        XCTAssertEqual(info.type, .socket)
        XCTAssertEqual(info.socket, "/tmp/mysql.sock")
        XCTAssertEqual(info.host, "")
    }

    func testSSHTunnelInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "internal-db.local"
        info.port = "3306"
        info.sshHost = "jump.example.com"
        info.sshUser = "tunnel"
        info.sshPort = "22"
        info.sshPassword = "sshpass"

        XCTAssertEqual(info.type, .sshTunnel)
        XCTAssertEqual(info.host, "internal-db.local")
        XCTAssertEqual(info.sshHost, "jump.example.com")
        XCTAssertEqual(info.sshUser, "tunnel")
        XCTAssertEqual(info.sshPort, "22")
        XCTAssertEqual(info.sshPassword, "sshpass")
    }

    func testBlankSSHPortDefersToSSHConfiguration() {
        for sshPort in ["", " \n\t "] {
            var info = SAConnectionInfo()
            info.sshPort = sshPort

            XCTAssertEqual(info.sshPortOverride, 0, "SSH port: \(sshPort.debugDescription)")
        }
    }

    func testValidSSHPortOverridesSSHConfiguration() {
        let ports = [("1", 1), ("2222", 2222), (" 2222 ", 2222), ("65535", 65535)]

        for (sshPort, expectedPort) in ports {
            var info = SAConnectionInfo()
            info.sshPort = sshPort

            XCTAssertEqual(info.sshPortOverride, expectedPort, "SSH port: \(sshPort)")
        }
    }

    func testInvalidSSHPortIsRejected() {
        for sshPort in ["0", "-1", "65536", "not-a-port"] {
            var info = SAConnectionInfo()
            info.sshPort = sshPort

            XCTAssertNil(info.sshPortOverride, "SSH port: \(sshPort)")
        }
    }

    func testAWSIAMInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .awsIAM
        info.host = "mydb.cluster.us-east-1.rds.amazonaws.com"
        info.port = "3306"
        info.user = "iam_user"
        info.useAWSIAMAuth = 1
        info.awsRegion = "us-east-1"
        info.awsProfile = "production"

        XCTAssertEqual(info.type, .awsIAM)
        XCTAssertEqual(info.useAWSIAMAuth, 1)
        XCTAssertEqual(info.awsRegion, "us-east-1")
        XCTAssertEqual(info.awsProfile, "production")
    }

    func testSSLEnabledPropagatesAllFields() {
        let info = SAConnectionInfoObjC()
        info.useSSL = 1
        info.sslKeyFileLocationEnabled = 1
        info.sslKeyFileLocation = "/path/key.pem"
        info.sslCertificateFileLocationEnabled = 1
        info.sslCertificateFileLocation = "/path/cert.pem"
        info.sslCACertFileLocationEnabled = 1
        info.sslCACertFileLocation = "/path/ca.pem"

        XCTAssertEqual(info.useSSL, 1)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 1)
        XCTAssertEqual(info.sslKeyFileLocation, "/path/key.pem")
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCertificateFileLocation, "/path/cert.pem")
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCACertFileLocation, "/path/ca.pem")
    }

    func testSSLDisabledByDefault() {
        let info = SAConnectionInfoObjC()
        XCTAssertEqual(info.useSSL, 0)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 0)
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 0)
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 0)
    }

    func testCompressionDefaults() {
        let info = SAConnectionInfoObjC()
        XCTAssertFalse(info.useCompression)

        info.useCompression = true
        XCTAssertTrue(info.useCompression)
    }

    func testTimeZoneModes() {
        let info = SAConnectionInfoObjC()

        info.timeZoneMode = .useServerTZ
        XCTAssertEqual(info.timeZoneMode, .useServerTZ)

        info.timeZoneMode = .useSystemTZ
        XCTAssertEqual(info.timeZoneMode, .useSystemTZ)

        info.timeZoneMode = .useFixedTZ
        info.timeZoneIdentifier = "America/New_York"
        XCTAssertEqual(info.timeZoneMode, .useFixedTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "America/New_York")
    }

    func testKeychainFieldsForServicePassthrough() {
        let info = SAConnectionInfoObjC()
        info.connectionSSHKeychainItemName = "SSH: jump"
        info.connectionSSHKeychainItemAccount = "tunnel@jump"

        XCTAssertEqual(info.connectionSSHKeychainItemName, "SSH: jump")
        XCTAssertEqual(info.connectionSSHKeychainItemAccount, "tunnel@jump")
    }

    func testUnchangedKeychainPasswordIsDeferredToConnectionDelegate() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.connectionKeychainItemName = "Favorite password"

        XCTAssertTrue(SAConnectionInfoObjC.shouldDeferMySQLPasswordToDelegate(
            for: info,
            password: SAConnectionInfoObjC.keychainPasswordPlaceholder,
            delegateAvailable: true
        ))
    }

    func testUnchangedKeychainPasswordWithoutDelegateIsPassedDirectly() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.connectionKeychainItemName = "Favorite password"

        XCTAssertFalse(SAConnectionInfoObjC.shouldDeferMySQLPasswordToDelegate(
            for: info,
            password: SAConnectionInfoObjC.keychainPasswordPlaceholder,
            delegateAvailable: false
        ))
    }

    func testExplicitPasswordOverrideIsPassedDirectly() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.connectionKeychainItemName = "Favorite password"

        XCTAssertFalse(SAConnectionInfoObjC.shouldDeferMySQLPasswordToDelegate(
            for: info,
            password: "temporary override",
            delegateAvailable: true
        ))
    }

    func testPasswordWithoutKeychainItemIsPassedDirectly() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel

        XCTAssertFalse(SAConnectionInfoObjC.shouldDeferMySQLPasswordToDelegate(
            for: info,
            password: SAConnectionInfoObjC.keychainPasswordPlaceholder,
            delegateAvailable: true
        ))
    }

    func testGeneratedCredentialsAreNeverDeferredToConnectionDelegate() {
        for connectionType in [SAConnectionType.awsIAM, .vault] {
            let info = SAConnectionInfoObjC()
            info.type = connectionType
            info.connectionKeychainItemName = "Favorite password"

            XCTAssertFalse(SAConnectionInfoObjC.shouldDeferMySQLPasswordToDelegate(
                for: info,
                password: SAConnectionInfoObjC.keychainPasswordPlaceholder,
                delegateAvailable: true
            ))
        }
    }

    func testSpecialSettingsForService() {
        let info = SAConnectionInfoObjC()
        info.allowDataLocalInfile = 1
        info.enableClearTextPlugin = 1
        info.requestServerPublicKey = 1

        XCTAssertEqual(info.allowDataLocalInfile, 1)
        XCTAssertEqual(info.enableClearTextPlugin, 1)
        XCTAssertEqual(info.requestServerPublicKey, 1)
    }

    /// Ensures localhost-specific grants still work through SSH tunnel forwarding.
    func testResolvedMySQLConnectHostPreservesLocalhostForSSHTunnelConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "localhost"

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "localhost")
    }

    /// Normalizes localhost spellings while still preserving loopback semantics.
    func testResolvedMySQLConnectHostCanonicalizesLocalhostCasingForSSHTunnelConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = " LocalHost "

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "localhost")
    }

    /// Ensures remote SSH target hosts do not leak into the local MySQL connect host.
    func testResolvedMySQLConnectHostUsesLoopbackForCustomHostForSSHTunnelConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "db.internal"

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "127.0.0.1")
    }

    /// Falls back to loopback when no explicit TCP host has been supplied.
    func testResolvedMySQLConnectHostDefaultsToLoopbackWhenBlank() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = ""

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "127.0.0.1")
    }

    /// Falls back to loopback for blank TCP favorites after trimming user input.
    func testResolvedMySQLConnectHostDefaultsToLoopbackForTCPIPConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .tcpIP
        info.host = "   "

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "127.0.0.1")
    }

    /// Preserves explicit TCP hosts for non-SSH connections.
    func testResolvedMySQLConnectHostPreservesCustomHostForTCPIPConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .tcpIP
        info.host = "db.internal"

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "db.internal")
    }

    /// Leaves socket connections without a TCP host override.
    func testResolvedMySQLConnectHostReturnsNilForSocketConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .socket

        XCTAssertNil(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info))
    }

    func testVaultInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .vault
        info.host = "mysql.internal"
        info.port = "3306"
        info.vaultHost = "vault.example.com"
        info.vaultPort = "443"
        info.vaultOIDCMount = "oidc"
        info.vaultCredentialsPath = "databases_credentials/creds/my-role"

        XCTAssertEqual(info.type, .vault)
        XCTAssertEqual(info.host, "mysql.internal")
        XCTAssertEqual(info.vaultHost, "vault.example.com")
        XCTAssertEqual(info.vaultPort, "443")
        XCTAssertEqual(info.vaultOIDCMount, "oidc")
        XCTAssertEqual(info.vaultCredentialsPath, "databases_credentials/creds/my-role")
        // Vault uses the DB host directly (TCP-identical) — not the Vault host
        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "mysql.internal")
    }
}
