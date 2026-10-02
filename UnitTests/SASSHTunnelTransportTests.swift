//
//  SASSHTunnelTransportTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The hidden transport preference and its environment encoding (Step 3 of
/// the SSH tunnel IPC plan).
final class SASSHTunnelTransportTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "com.sequel-ace.tests.SASSHTunnelTransportTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// Step 5a made the socket the default and 6.0.0 shipped it; issue #2689
    /// showed it failing outright on some machines, so 6.0.1 defaults to
    /// Distributed Objects again and the socket is opt-in.
    func testAbsentPreferenceMeansDistributedObjectsAgainAfterIssue2689() {
        XCTAssertEqual(SASSHTunnelTransportSelection.selectedTransport(from: defaults), .distributedObjects)
        XCTAssertEqual(SASSHTunnelTransportSelection.defaultTransport, .distributedObjects)
    }

    func testOptingIntoTheSocketIsTheExplicitTrue() {
        defaults.set(true, forKey: "SPSSHTunnelUseSocketTransport")
        XCTAssertEqual(SASSHTunnelTransportSelection.selectedTransport(from: defaults), .socket)
    }

    func testExplicitFalseStaysDistributedObjects() {
        defaults.set(false, forKey: "SPSSHTunnelUseSocketTransport")
        XCTAssertEqual(SASSHTunnelTransportSelection.selectedTransport(from: defaults), .distributedObjects)
    }

    func testPreferenceSelectsTheSocketOrDistributedObjects() {
        defaults.set(true, forKey: SASSHTunnelTransportSelection.defaultsKey)
        XCTAssertEqual(SASSHTunnelTransportSelection.selectedTransport(from: defaults), .socket)
        defaults.set(false, forKey: SASSHTunnelTransportSelection.defaultsKey)
        XCTAssertEqual(SASSHTunnelTransportSelection.selectedTransport(from: defaults), .distributedObjects)
    }

    func testEnvironmentValuesMatchWhatTheAssistantLooksFor() {
        XCTAssertEqual(SASSHTunnelTransport.socket.environmentValue, "socket")
        XCTAssertEqual(SASSHTunnelTransport.distributedObjects.environmentValue, "distributedObjects")
        XCTAssertEqual(SASSHTunnelTransportSelection.environmentValue(for: .socket), SASSHTunnelSocketIO.TransportValue.socket)
        XCTAssertEqual(SASSHTunnelTransportSelection.transportEnvironmentKey, "SP_CONNECTION_TRANSPORT")
        XCTAssertEqual(SASSHTunnelTransportSelection.socketPathEnvironmentKey, "SP_CONNECTION_SOCKET_PATH")
    }
}
