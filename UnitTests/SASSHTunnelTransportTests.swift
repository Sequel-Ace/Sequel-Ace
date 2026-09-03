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

    func testAbsentPreferenceMeansTheDefaultWhichIsTheSocketSinceStep5() {
        XCTAssertEqual(SASSHTunnelTransportSelection.selectedTransport(from: defaults), .socket)
        XCTAssertEqual(SASSHTunnelTransportSelection.defaultTransport, .socket)
    }

    func testRollbackIsTheExplicitFalse() {
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
