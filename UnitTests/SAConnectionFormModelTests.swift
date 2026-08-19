//
//  SAConnectionFormModelTests.swift
//  Unit Tests
//
//  Pins the behaviour of the SwiftUI connection-form model (Phase C2):
//  ObjC bridging round-trips, effective-name fallback, the
//  connect-button gate, and the wiring into the D3 validator.
//

import Combine
import XCTest

final class SAConnectionFormModelTests: XCTestCase {

    // MARK: - Defaults & bridging

    func testDefaultsMatchBlankConnectionInfo() {
        let model = SAConnectionFormModel()

        XCTAssertEqual(model.info.type, .tcpIP)
        XCTAssertEqual(model.info.name, "")
        XCTAssertEqual(model.info.host, "")
        XCTAssertEqual(model.info.user, "")
        XCTAssertEqual(model.info.password, "")
        XCTAssertEqual(model.info.database, "")
        XCTAssertEqual(model.info.port, "")
    }

    func testInitFromObjCWrapperCopiesValues() {
        let objc = SAConnectionInfoObjC()
        objc.host = "db.example.com"
        objc.user = "app"
        objc.port = "3307"

        let model = SAConnectionFormModel(objc: objc)

        XCTAssertEqual(model.info.host, "db.example.com")
        XCTAssertEqual(model.info.user, "app")
        XCTAssertEqual(model.info.port, "3307")
    }

    func testApplyToObjCWrapperRoundTrips() {
        let model = SAConnectionFormModel()
        model.info.host = "db.example.com"
        model.info.database = "shop"
        model.info.password = "secret"
        model.info.requestServerPublicKey = 1

        let objc = SAConnectionInfoObjC()
        model.apply(to: objc)

        XCTAssertEqual(objc.host, "db.example.com")
        XCTAssertEqual(objc.database, "shop")
        XCTAssertEqual(objc.password, "secret")
        XCTAssertEqual(objc.requestServerPublicKey, 1)
    }

    func testEditsDoNotLeakBackIntoSourceWrapper() {
        // The model holds a value copy — editing it must not mutate the
        // wrapper it was created from until apply(to:) is called.
        let objc = SAConnectionInfoObjC()
        objc.host = "original"

        let model = SAConnectionFormModel(objc: objc)
        model.info.host = "edited"

        XCTAssertEqual(objc.host, "original")
    }

    // MARK: - Effective name

    func testEffectiveNamePrefersUserEnteredName() {
        let model = SAConnectionFormModel()
        model.info.name = "Prod"
        model.info.host = "db.example.com"

        XCTAssertEqual(model.effectiveName, "Prod")
    }

    func testEffectiveNameFallsBackToGeneratedHostName() {
        let model = SAConnectionFormModel()
        model.info.host = "db.example.com"

        XCTAssertEqual(model.effectiveName, "db.example.com")
    }

    func testEffectiveNameAppendsDatabase() {
        let model = SAConnectionFormModel()
        model.info.host = "db.example.com"
        model.info.database = "shop"

        XCTAssertEqual(model.effectiveName, "db.example.com/shop")
    }

    func testEffectiveNameEmptyWithoutHost() {
        XCTAssertEqual(SAConnectionFormModel().effectiveName, "")
    }

    func testEffectiveNameIgnoresWhitespaceOnlyName() {
        let model = SAConnectionFormModel()
        model.info.name = "   "
        model.info.host = "db.example.com"

        XCTAssertEqual(model.effectiveName, "db.example.com")
    }

    // MARK: - Connect gate

    func testCanAttemptConnectionRequiresHostForTCPIP() {
        let model = SAConnectionFormModel()
        XCTAssertFalse(model.canAttemptConnection)

        model.info.host = "db.example.com"
        XCTAssertTrue(model.canAttemptConnection)

        model.info.host = "   "
        XCTAssertFalse(model.canAttemptConnection)
    }

    func testCanAttemptConnectionAlwaysTrueForSocket() {
        let model = SAConnectionFormModel()
        model.info.type = .socket

        XCTAssertTrue(model.canAttemptConnection)
    }

    func testCanAttemptConnectionRequiresHostForAWSAndVault() {
        for type in [SAConnectionType.awsIAM, .vault] {
            let model = SAConnectionFormModel()
            model.info.type = type
            XCTAssertFalse(model.canAttemptConnection, "\(type) without host")

            model.info.host = "db.example.com"
            XCTAssertTrue(model.canAttemptConnection, "\(type) with host")
        }
    }

    func testCanAttemptConnectionForSSHTunnelAcceptsHostOrRemoteSocket() {
        let model = SAConnectionFormModel()
        model.info.type = .sshTunnel

        // Neither host nor remote socket: gated.
        XCTAssertFalse(model.canAttemptConnection)

        // MySQL host alone is enough.
        model.info.host = "db.example.com"
        XCTAssertTrue(model.canAttemptConnection)

        // A remote socket path alone is enough too — the validator skips
        // the host requirement for socket-targeting tunnels and
        // SAConnectionService connects through the socket.
        model.info.host = ""
        model.info.sshRemoteSocketPath = "/var/run/mysqld/mysqld.sock"
        XCTAssertTrue(model.canAttemptConnection)

        // Whitespace-only values don't count.
        model.info.sshRemoteSocketPath = "   "
        XCTAssertFalse(model.canAttemptConnection)
    }

    func testGateAgreesWithValidatorForRemoteSocketTunnel() {
        // The P2 regression this pins: a remote-socket SSH favorite must
        // be submittable — the gate may never be stricter than validate().
        let model = SAConnectionFormModel()
        model.info.type = .sshTunnel
        model.info.sshHost = "bastion.example.com"
        model.info.sshRemoteSocketPath = "/var/run/mysqld/mysqld.sock"

        XCTAssertTrue(model.canAttemptConnection)
        XCTAssertNil(model.validate())
    }

    // MARK: - Validation wiring (full rules pinned by D3's own tests)

    func testValidateFailsWithHostMissingForEmptyTCPIPHost() {
        let failure = SAConnectionFormModel().validate()

        XCTAssertEqual(failure?.kind, .hostMissing)
        XCTAssertFalse(failure?.alertTitle.isEmpty ?? true)
        XCTAssertFalse(failure?.alertMessage.isEmpty ?? true)
    }

    func testValidatePassesWithHostProvided() {
        let model = SAConnectionFormModel()
        model.info.host = "db.example.com"

        XCTAssertNil(model.validate())
    }

    // MARK: - Observability

    func testMutatingInfoPublishesChange() {
        let model = SAConnectionFormModel()
        var changes = 0
        let cancellable = model.objectWillChange.sink { changes += 1 }

        model.info.host = "db.example.com"
        model.info.port = "3307"

        XCTAssertEqual(changes, 2)
        cancellable.cancel()
    }

    // MARK: - C2b: time zone choice

    func testTimeZoneChoiceDefaultsToServer() {
        XCTAssertEqual(SAConnectionFormModel().timeZoneChoice, .server)
    }

    func testTimeZoneChoiceRoundTripsThroughTheStoredPair() {
        let model = SAConnectionFormModel()

        model.timeZoneChoice = .fixed("Europe/Prague")
        XCTAssertEqual(model.info.timeZoneMode, .useFixedTZ)
        XCTAssertEqual(model.info.timeZoneIdentifier, "Europe/Prague")
        XCTAssertEqual(model.timeZoneChoice, .fixed("Europe/Prague"))
    }

    /// `-didChangeSelectedTimeZone:` clears the identifier when leaving the
    /// fixed mode; a stale one would otherwise be written to the favorite.
    func testLeavingFixedModeClearsTheIdentifier() {
        let model = SAConnectionFormModel()
        model.timeZoneChoice = .fixed("Europe/Prague")

        model.timeZoneChoice = .system
        XCTAssertEqual(model.info.timeZoneMode, .useSystemTZ)
        XCTAssertEqual(model.info.timeZoneIdentifier, "")

        model.timeZoneChoice = .server
        XCTAssertEqual(model.info.timeZoneMode, .useServerTZ)
        XCTAssertEqual(model.info.timeZoneIdentifier, "")
    }

    /// The popup has no item that could show "fixed, but no identifier",
    /// so that stored combination reads back as the server default.
    func testFixedModeWithoutAnIdentifierDegradesToServer() {
        let model = SAConnectionFormModel()
        model.info.timeZoneMode = .useFixedTZ
        model.info.timeZoneIdentifier = ""

        XCTAssertEqual(model.timeZoneChoice, .server)
    }

    // MARK: - C2b: time zone menu

    func testTimeZoneMenuLeadsWithTheTwoRelativeChoices() {
        let menu = SATimeZoneMenuEntry.menu(identifiers: ["Europe/Prague"])

        XCTAssertEqual(menu.first, .choice(.server))
        XCTAssertEqual(menu.dropFirst().first, .separator(afterPrefix: ""))
        XCTAssertEqual(menu.dropFirst(2).first, .choice(.system))
    }

    func testTimeZoneMenuSeparatesOnEveryPrefixChange() {
        let menu = SATimeZoneMenuEntry.menu(identifiers: ["Europe/Prague", "Europe/Berlin", "America/New_York", "UTC"])
        let afterRelative = Array(menu.dropFirst(3))

        XCTAssertEqual(afterRelative, [
            .separator(afterPrefix: "America"),
            .choice(.fixed("America/New_York")),
            .separator(afterPrefix: "Europe"),
            .choice(.fixed("Europe/Berlin")),
            .choice(.fixed("Europe/Prague")),
            .separator(afterPrefix: "UTC"),
            .choice(.fixed("UTC")),
        ])
    }

    func testTimeZoneMenuSortsCaseInsensitively() {
        let menu = SATimeZoneMenuEntry.menu(identifiers: ["Zulu", "america/x", "America/A"])
        let identifiers = menu.compactMap { entry -> String? in
            if case .choice(.fixed(let identifier)) = entry { return identifier }
            return nil
        }

        XCTAssertEqual(identifiers, ["America/A", "america/x", "Zulu"])
    }

    /// The real menu is what ships; make sure it is populated and that every
    /// entry is unique, since the SwiftUI picker keys its rows by value.
    func testDefaultTimeZoneMenuIsPopulatedAndUnique() {
        let menu = SATimeZoneMenuEntry.menu()

        XCTAssertGreaterThan(menu.count, 3)
        XCTAssertEqual(Set(menu).count, menu.count)
    }

    // MARK: - C2b: flag bridges

    func testFlagBridgesReadNonZeroAsOn() {
        let model = SAConnectionFormModel()
        model.info.useSSL = 1
        model.info.allowDataLocalInfile = 2  // ObjC -boolValue semantics: any non-zero

        XCTAssertTrue(model.useSSL)
        XCTAssertTrue(model.allowDataLocalInfile)
        XCTAssertFalse(model.enableClearTextPlugin)
    }

    func testFlagBridgesWriteOneAndZero() {
        let model = SAConnectionFormModel()

        model.useSSL = true
        model.sshKeyLocationEnabled = true
        model.sslCACertFileLocationEnabled = true
        XCTAssertEqual(model.info.useSSL, 1)
        XCTAssertEqual(model.info.sshKeyLocationEnabled, 1)
        XCTAssertEqual(model.info.sslCACertFileLocationEnabled, 1)

        model.useSSL = false
        XCTAssertEqual(model.info.useSSL, 0)
    }

    func testEveryFlagBridgeTargetsItsOwnField() {
        let model = SAConnectionFormModel()

        model.useSSL = true
        model.allowDataLocalInfile = true
        model.enableClearTextPlugin = true
        model.requestServerPublicKey = true
        model.sshKeyLocationEnabled = true
        model.sslKeyFileLocationEnabled = true
        model.sslCertificateFileLocationEnabled = true
        model.sslCACertFileLocationEnabled = true

        XCTAssertEqual(
            [model.info.useSSL, model.info.allowDataLocalInfile, model.info.enableClearTextPlugin,
             model.info.requestServerPublicKey, model.info.sshKeyLocationEnabled,
             model.info.sslKeyFileLocationEnabled, model.info.sslCertificateFileLocationEnabled,
             model.info.sslCACertFileLocationEnabled],
            Array(repeating: 1, count: 8)
        )
    }

    // MARK: - C2b: per-type form shape

    /// AWS IAM enables SSL and the cleartext plugin itself, so its tab shows
    /// neither toggle nor an SSL details container — it shows a note instead.
    func testAWSIAMForcesSSLAndHidesTheSecurityToggles() {
        let model = SAConnectionFormModel()
        model.info.type = .awsIAM
        model.useSSL = true

        XCTAssertTrue(model.forcesSSL)
        XCTAssertFalse(model.showsSSLToggle)
        XCTAssertFalse(model.showsClearTextPluginToggle)
        XCTAssertFalse(model.showsRequestServerPublicKeyToggle)
        XCTAssertFalse(model.showsSSLFileOptions, "AWS IAM has no SSL details container in the XIB")
    }

    func testOtherTypesOfferTheSecurityToggles() {
        for type in [SAConnectionType.tcpIP, .socket, .sshTunnel, .vault] {
            let model = SAConnectionFormModel()
            model.info.type = type

            XCTAssertFalse(model.forcesSSL, "\(type)")
            XCTAssertTrue(model.showsSSLToggle, "\(type)")
            XCTAssertTrue(model.showsClearTextPluginToggle, "\(type)")
            XCTAssertTrue(model.showsRequestServerPublicKeyToggle, "\(type)")
        }
    }

    /// The XIB reveals the SSL file container only while "Require SSL" is on.
    func testSSLFileOptionsFollowTheSSLToggle() {
        let model = SAConnectionFormModel()
        model.info.type = .tcpIP

        XCTAssertFalse(model.showsSSLFileOptions)
        model.useSSL = true
        XCTAssertTrue(model.showsSSLFileOptions)
    }

    // MARK: - C2b: connect gate across the types

    func testSocketConnectionsNeedNoHost() {
        let model = SAConnectionFormModel()
        model.info.type = .socket

        XCTAssertTrue(model.canAttemptConnection)
    }

    func testSSHTunnelAcceptsEitherAHostOrARemoteSocket() {
        let model = SAConnectionFormModel()
        model.info.type = .sshTunnel
        XCTAssertFalse(model.canAttemptConnection)

        model.info.sshRemoteSocketPath = "/var/run/mysqld/mysqld.sock"
        XCTAssertTrue(model.canAttemptConnection)

        model.info.sshRemoteSocketPath = ""
        model.info.host = "db.internal"
        XCTAssertTrue(model.canAttemptConnection)
    }

    func testAWSAndVaultRequireAHost() {
        for type in [SAConnectionType.awsIAM, .vault] {
            let model = SAConnectionFormModel()
            model.info.type = type
            XCTAssertFalse(model.canAttemptConnection, "\(type)")

            model.info.host = "db.example.com"
            XCTAssertTrue(model.canAttemptConnection, "\(type)")
        }
    }

    // MARK: - C2b: vault mount / role split

    func testVaultMountAndRoleJoinIntoTheStoredPath() {
        let model = SAConnectionFormModel()
        model.vaultMount = "databases_credentials"
        model.vaultCredentialsRole = "readonly"

        XCTAssertEqual(model.info.vaultCredentialsPath, "databases_credentials/creds/readonly")
    }

    /// The halves have to be stored, not derived: joining returns "" until a
    /// role exists, so a mount typed first would be lost on the round trip.
    func testMountSurvivesBeingTypedBeforeTheRole() {
        let model = SAConnectionFormModel()
        model.vaultMount = "databases_credentials"

        XCTAssertEqual(model.info.vaultCredentialsPath, "")
        XCTAssertEqual(model.vaultMount, "databases_credentials")

        model.vaultCredentialsRole = "readonly"
        XCTAssertEqual(model.info.vaultCredentialsPath, "databases_credentials/creds/readonly")
    }

    func testInitSplitsAnExistingCredentialsPath() {
        var info = SAConnectionInfo()
        info.vaultCredentialsPath = "databases_credentials/creds/readonly"

        let model = SAConnectionFormModel(info: info)
        XCTAssertEqual(model.vaultMount, "databases_credentials")
        XCTAssertEqual(model.vaultCredentialsRole, "readonly")
    }

    /// Loading a favorite replaces `info` wholesale; the two halves must follow.
    func testReplacingInfoResplitsTheCredentialsPath() {
        let model = SAConnectionFormModel()
        model.vaultMount = "old"
        model.vaultCredentialsRole = "role"

        var loaded = SAConnectionInfo()
        loaded.vaultCredentialsPath = "team/creds/writer"
        model.info = loaded

        XCTAssertEqual(model.vaultMount, "team")
        XCTAssertEqual(model.vaultCredentialsRole, "writer")
        XCTAssertEqual(model.info.vaultCredentialsPath, "team/creds/writer")
    }

    /// Editing the halves must not be mistaken for an external change and
    /// bounce back — the guard in the didSet pair is what prevents it.
    func testEditingHalvesDoesNotResplitThem() {
        let model = SAConnectionFormModel()
        model.vaultMount = "databases_credentials"
        model.vaultCredentialsRole = "readonly"

        // Clearing the mount leaves a bare role, which must stay in the role
        // half rather than being re-parsed into the mount.
        model.vaultMount = ""

        XCTAssertEqual(model.info.vaultCredentialsPath, "readonly")
        XCTAssertEqual(model.vaultMount, "")
        XCTAssertEqual(model.vaultCredentialsRole, "readonly")
    }

    /// A full path pasted into the Role field is honoured verbatim by
    /// SAVaultCredentialsPath; the model must not double-prefix it.
    func testFullPathPastedIntoTheRoleHalfIsHonoured() {
        let model = SAConnectionFormModel()
        model.vaultMount = "ignored"
        model.vaultCredentialsRole = "team/creds/writer"

        XCTAssertEqual(model.info.vaultCredentialsPath, "team/creds/writer")
    }

    // MARK: - C2b: generated name across the types

    func testSocketConnectionsNameThemselvesLocalhost() {
        let model = SAConnectionFormModel()
        model.info.type = .socket

        XCTAssertEqual(model.effectiveName, "localhost")

        model.info.database = "sakila"
        XCTAssertEqual(model.effectiveName, "localhost/sakila")
    }

    func testNonSocketTypesGenerateFromTheHost() {
        for type in [SAConnectionType.tcpIP, .sshTunnel, .awsIAM, .vault] {
            let model = SAConnectionFormModel()
            model.info.type = type

            XCTAssertEqual(model.effectiveName, "", "\(type) with no host")

            model.info.host = "db.example.com"
            XCTAssertEqual(model.effectiveName, "db.example.com", "\(type)")
        }
    }
}
