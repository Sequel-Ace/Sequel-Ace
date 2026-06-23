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
}
