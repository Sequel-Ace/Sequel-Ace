//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SALocalNetworkPermissionCheckerTests: XCTestCase {

    func testLocalNetworkPermissionCheckerReturnsFalseForEmptyHost() {
        XCTAssertFalse(
            SALocalNetworkPermissionChecker.isLocalNetworkAccessDenied(
                forHost: "   ",
                port: 3306,
                timeout: 0.1
            )
        )
    }

    func testLocalNetworkPermissionCheckerReturnsFalseForInvalidPort() {
        XCTAssertFalse(
            SALocalNetworkPermissionChecker.isLocalNetworkAccessDenied(
                forHost: "192.168.1.20",
                port: 0,
                timeout: 0.1
            )
        )
    }

    /// Verifies that an access-denied answer is never probed: the server answered, so the
    /// host was reached, whatever the user or host is called - even when the message holds
    /// a phrase that would otherwise open the probe.
    func testAccessDeniedIsNeverProbed() {
        XCTAssertFalse(SALocalNetworkPermissionChecker.shouldProbe(
            afterMySQLErrorID: 1045,
            message: "Access denied for user 'network_admin'@'192.168.1.5' (using password: YES)"
        ))
        XCTAssertFalse(SALocalNetworkPermissionChecker.shouldProbe(
            afterMySQLErrorID: 1045,
            message: "Access denied for user 'timed out'@'no route to host' (using password: YES)"
        ))
    }

    /// Verifies that the word "network" in a message does not count as a network failure.
    /// A host or user name holding it used to be reported as a denied Local Network
    /// permission, which hid the real error behind the permission alert.
    func testTheWordNetworkInAMessageIsNoReasonToProbe() {
        XCTAssertFalse(SALocalNetworkPermissionChecker.shouldProbe(
            afterMySQLErrorID: 2005,
            message: "Unknown MySQL server host 'db.network.example' (8)"
        ))
        XCTAssertFalse(SALocalNetworkPermissionChecker.shouldProbe(
            afterMySQLErrorID: 1130,
            message: "Host 'network-gateway' is not allowed to connect to this MySQL server"
        ))
    }

    /// Verifies that a failure to reach the host is probed, by error number or by message.
    func testFailuresToReachTheHostAreProbed() {
        XCTAssertTrue(SALocalNetworkPermissionChecker.shouldProbe(
            afterMySQLErrorID: 2003,
            message: "Can't connect to MySQL server on '192.168.1.20:3306' (65)"
        ))
        XCTAssertTrue(SALocalNetworkPermissionChecker.shouldProbe(afterMySQLErrorID: 2002, message: ""))
        XCTAssertTrue(SALocalNetworkPermissionChecker.shouldProbe(
            afterMySQLErrorID: 2013,
            message: "Lost connection to MySQL server at 'handshake', system error: 60 (Operation timed out)"
        ))
        XCTAssertTrue(SALocalNetworkPermissionChecker.shouldProbe(afterMySQLErrorID: 0, message: "No route to host"))
        XCTAssertTrue(SALocalNetworkPermissionChecker.shouldProbe(afterMySQLErrorID: 0, message: "Network is unreachable"))
    }

    /// Verifies that an attempt without an error number or message is not probed.
    func testNoErrorIsNoReasonToProbe() {
        XCTAssertFalse(SALocalNetworkPermissionChecker.shouldProbe(afterMySQLErrorID: 0, message: ""))
    }
}
