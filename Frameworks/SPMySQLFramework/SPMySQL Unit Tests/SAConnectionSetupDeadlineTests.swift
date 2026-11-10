//
//  SAConnectionSetupDeadlineTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import XCTest
@testable import SPMySQL

/// What the server does about a statement the connection is waiting on.
private enum SAServerReply {
    /// The reply comes at once.
    case atOnce
    /// The reply comes after this long: a slow but healthy connection.
    case after(TimeInterval)
    /// The reply never comes: a tunnel whose far end has stopped replying.
    case never
    /// The statement is done after this long - its reply was in - with no further wait on the socket.
    case doneAfter(TimeInterval)
}

/// Replaces only the transport: a local socket pair stands in for the session, the test holding
/// one end as the server. The setup phase and the bracket it puts around the statements, the
/// reconnect and its restoration are the framework's own code. Only the statements themselves are
/// stood in for, each as a wait on the socket for a reply the test's server sends late, or never.
private class SASetupDeadlineConnection: SPMySQLConnection {
    private(set) var pairs: [(client: Int32, server: Int32)] = []

    var setupReply: SAServerReply = .atOnce
    /// The reply to the last setup statement, the largest query size.
    var lastSetupReply: SAServerReply = .atOnce
    var restoreReply: SAServerReply = .atOnce
    /// What the wait for the reply ended with: the byte count `read` returned, nil when nothing was waited for.
    var setupWaitEndedWith: Int?
    var restoreWaitEndedWith: Int?
    var setupTook: TimeInterval = 0
    var restoreTook: TimeInterval = 0
    /// How often the connection closed its session - what a lost setup has to end in.
    var sessionsClosed = 0
    /// How often a session was opened: the attempt, and each retry.
    var handshakes = 0
    /// After this many handshakes the server answers at once, so an attempt that would otherwise
    /// retry without end comes to an end the test can see.
    var stopsStallingAfterHandshakes: Int?

    /// The server's end of the current session.
    var server: Int32 { pairs.last?.server ?? -1 }
    /// The connection's end of the current session.
    var client: Int32 { pairs.last?.client ?? -1 }

    /// Opens a session: a fresh socket pair.
    @discardableResult
    func openSession() -> Bool {
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            return false
        }
        pairs.append((client: pair[0], server: pair[1]))
        return true
    }

    /// Closes every socket the test opened.
    func closeEverything() {
        for pair in pairs {
            Darwin.close(pair.client)
            Darwin.close(pair.server)
        }
        pairs = []
    }

    /// Whether the server can still get a byte through to the connection's end.
    func theSocketStillCarriesAReply() -> Bool {
        var reply: UInt8 = 1
        guard Darwin.write(server, &reply, 1) == 1 else {
            return false
        }
        var byte: UInt8 = 0
        return Darwin.read(client, &byte, 1) == 1
    }

    // The deadline is armed on the session's socket, which here is the pair's connection end.
    @objc(_socketForSetupDeadline) func socketForSetupDeadline() -> Int32 {
        client
    }

    // The handshake: a new session, up. What follows it - the setup - is the framework's own.
    @objc(_connectUsingConnectTimeout:) func shakeHands(_ connectTimeoutOrZero: UInt) -> Bool {
        guard openSession() else {
            return false
        }
        handshakes += 1
        setValue(SPMySQLConnected.rawValue, forKey: "state")
        return perform(Selector(("_runSessionSetup"))) != nil
    }

    @objc(_updateConnectionVariables) func readTheServersVariables() {
        setupTook = wait(for: reply(setupReply), endedWith: &setupWaitEndedWith)
        giveTheSessionUpIfTheWaitEndedWithoutAReply(setupWaitEndedWith)
    }

    @objc(_updateMaxQuerySize) func readTheLargestQuerySize() {
        var ended: Int?
        setupTook += wait(for: reply(lastSetupReply), endedWith: &ended)
        if ended != nil {
            setupWaitEndedWith = ended
        }
        giveTheSessionUpIfTheWaitEndedWithoutAReply(ended)
    }

    /// The connection's own query path reports a read that ended without a reply to the deadline
    /// the statement ran under, as a lost session; the statement is stood in for, so that is too.
    private func giveTheSessionUpIfTheWaitEndedWithoutAReply(_ ended: Int?) {
        guard ended == 0 else {
            return
        }
        (value(forKey: "activeSetupDeadline") as? SAConnectionSetupDeadline)?.noteAStatementLostTheSession()
    }

    // A restore with nothing left to check at its end - no time zone - reports success whatever
    // happened to its earlier statements; the loss is reported the way the query path reports it.
    @objc(_restoreSessionStateAfterReconnectWithDatabase:encoding:encodingUsesLatin1Transport:timeZoneIdentifier:)
    func restoreTheSession(_ database: String?, encoding: String?, encodingUsesLatin1Transport: Bool, timeZoneIdentifier: String?) -> Bool {
        restoreTook = wait(for: restoreReply, endedWith: &restoreWaitEndedWith)
        giveTheSessionUpIfTheWaitEndedWithoutAReply(restoreWaitEndedWith)
        return true
    }

    @objc(_disconnectPreservingProxyReconnect:) func closeSession(_ preserveProxy: Bool) {
        sessionsClosed += 1
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }

    /// The reply as told, unless the server has been told to stop stalling by now.
    private func reply(_ reply: SAServerReply) -> SAServerReply {
        if let limit = stopsStallingAfterHandshakes, handshakes > limit {
            return .atOnce
        }
        return reply
    }

    /// Waits on the connection's socket the way a statement waits for its reply, with the server answering as told.
    private func wait(for reply: SAServerReply, endedWith ended: inout Int?) -> TimeInterval {
        // Each wait reports its own end: a retry must not inherit how the attempt before it ended.
        ended = nil
        let start = Date()
        switch reply {
        case .atOnce:
            return 0
        case .doneAfter(let delay):
            Thread.sleep(forTimeInterval: delay)
        case .after(let delay):
            let server = self.server
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                var reply: UInt8 = 1
                _ = Darwin.write(server, &reply, 1)
            }
            var byte: UInt8 = 0
            ended = Darwin.read(client, &byte, 1)
        case .never:
            var byte: UInt8 = 0
            ended = Darwin.read(client, &byte, 1)
        }
        return Date().timeIntervalSince(start)
    }
}

/// A connection whose session has no socket a deadline could be armed on.
private final class SANoSocketForADeadlineConnection: SASetupDeadlineConnection {
    @objc(_socketForSetupDeadline) override func socketForSetupDeadline() -> Int32 {
        -1
    }
}

/// The same connection on a budget short enough to wait out in a test.
private final class SAShortSetupBudgetConnection: SASetupDeadlineConnection {
    var budget: TimeInterval = 0.4

    @objc(_setupDeadlineSeconds) func setupDeadlineSeconds() -> TimeInterval {
        budget
    }
}

final class SAConnectionSetupDeadlineTests: XCTestCase {
    private var openDescriptors: [Int32] = []

    override func tearDown() {
        for descriptor in openDescriptors {
            Darwin.close(descriptor)
        }
        openDescriptors = []
        super.tearDown()
    }

    /// A socket pair, both ends closed by `tearDown`.
    private func socketPair() throws -> (client: Int32, server: Int32) {
        var pair: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0, "no local socket pair available")
        openDescriptors.append(contentsOf: pair)
        return (client: pair[0], server: pair[1])
    }

    /// Reads one byte from the socket, and says how the read ended and how long it took.
    private func readOneByte(from socket: Int32) -> (ended: Int, took: TimeInterval) {
        let start = Date()
        var byte: UInt8 = 0
        let ended = Darwin.read(socket, &byte, 1)
        return (ended, Date().timeIntervalSince(start))
    }

    // MARK: - The deadline itself

    /// A wait for a reply that never comes ends when the budget runs out - as a closed
    /// connection, which is the error the connection already handles, not as a hang.
    func testAWaitForAReplyThatNeverComesEndsWithinTheBudget() throws {
        let pair = try socketPair()
        let deadline = try SAConnectionSetupDeadline.deadline(forSocket: pair.client, seconds: 0.3)

        let read = readOneByte(from: pair.client)

        XCTAssertEqual(read.ended, 0, "the wait ends as a closed connection, not as an error")
        XCTAssertGreaterThanOrEqual(read.took, 0.25)
        XCTAssertLessThan(read.took, 1.5)
        XCTAssertTrue(deadline.endedTheWaitOnTheSocket)
        XCTAssertTrue(deadline.disarm(), "lifting a deadline that already fired says so")
    }

    /// A reply inside the budget is read, and once the deadline is lifted the socket carries on
    /// without a limit: the ordinary policy for the long queries people run on purpose.
    func testAReplyInsideTheBudgetIsReadAndTheSocketKeptAfterwards() throws {
        let pair = try socketPair()
        let deadline = try SAConnectionSetupDeadline.deadline(forSocket: pair.client, seconds: 0.4)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            var reply: UInt8 = 1
            _ = Darwin.write(pair.server, &reply, 1)
        }

        XCTAssertEqual(readOneByte(from: pair.client).ended, 1)
        XCTAssertFalse(deadline.disarm(), "the budget had not run out")
        XCTAssertFalse(deadline.endedTheWaitOnTheSocket)

        // Well past the budget, a reply still gets through: nothing shut the socket down.
        Thread.sleep(forTimeInterval: 0.6)
        var reply: UInt8 = 2
        XCTAssertEqual(Darwin.write(pair.server, &reply, 1), 1)
        XCTAssertEqual(readOneByte(from: pair.client).ended, 1)
    }

    /// The deadline names the socket, not its descriptor number: a socket closed while the
    /// deadline stands can give its number to another, and that one is left alone.
    func testTheDeadlineNamesTheSocketNotItsNumber() throws {
        var first: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &first) == 0, "no local socket pair available")
        let deadline = try SAConnectionSetupDeadline.deadline(forSocket: first[0], seconds: 0.2)

        // The connection closes its descriptors; the next socket pair takes the lowest free numbers.
        Darwin.close(first[0])
        Darwin.close(first[1])
        let second = try socketPair()
        XCTAssertEqual(second.client, first[0], "the number was reused, which is the case this guards")

        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(deadline.endedTheWaitOnTheSocket, "the deadline fired, at the socket it was armed on")
        var reply: UInt8 = 1
        XCTAssertEqual(Darwin.write(second.server, &reply, 1), 1)
        XCTAssertEqual(readOneByte(from: second.client).ended, 1, "the socket that inherited the number is untouched")
    }

    /// Nothing to shut down, nothing armed - and the caller is told which descriptor failure it was.
    func testAMissingDescriptorHasNoDeadline() {
        XCTAssertThrowsError(try SAConnectionSetupDeadline.deadline(forSocket: -1, seconds: 1)) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(EBADF))
        }
        XCTAssertThrowsError(try SAConnectionSetupDeadline.deadline(forSocket: 1 << 20, seconds: 1), "a number that is no descriptor cannot be duplicated") { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
        }
    }

    /// What the phase decides: it goes on while the session is connected and no statement lost it;
    /// it ends well only if, on top of that, the deadline never had to end a wait.
    func testThePhaseDecidesFromTheSessionTheStatementsAndTheDeadline() throws {
        let pair = try socketPair()

        let quiet = try SAConnectionSetupDeadline.deadline(forSocket: pair.client, seconds: 5)
        XCTAssertTrue(quiet.phaseContinues(whileConnected: true))
        XCTAssertFalse(quiet.phaseContinues(whileConnected: false), "a session that is gone has no phase to go on with")
        XCTAssertTrue(quiet.endPhase(whileConnected: true))

        let lost = try SAConnectionSetupDeadline.deadline(forSocket: pair.client, seconds: 5)
        lost.noteAStatementLostTheSession()
        XCTAssertFalse(lost.phaseContinues(whileConnected: true), "a statement lost the session, connected or not")
        XCTAssertFalse(lost.endPhase(whileConnected: true))

        let late = try SAConnectionSetupDeadline.deadline(forSocket: pair.client, seconds: 0.1)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(late.phaseContinues(whileConnected: true), "the statements themselves report a loss, not the clock")
        XCTAssertFalse(late.endPhase(whileConnected: true), "but a deadline that ran out has shut the session down")
        XCTAssertTrue(late.endedTheWaitOnTheSocket)
    }

    // MARK: - Through the connection

    private func shortBudgetConnection() -> SAShortSetupBudgetConnection {
        let connection = SAShortSetupBudgetConnection()
        connection.useKeepAlive = false
        connection.timeout = 0
        return connection
    }

    /// The budget comes from the check budget, and is setup's own.
    func testTheConnectionTakesSetupsBudgetFromTheCheckBudget() {
        let connection = SASetupDeadlineConnection()
        let selector = #selector(SAShortSetupBudgetConnection.setupDeadlineSeconds)
        typealias Seconds = @convention(c) (AnyObject, Selector) -> TimeInterval
        let seconds = unsafeBitCast(connection.method(for: selector), to: Seconds.self)

        connection.timeout = 0
        XCTAssertEqual(seconds(connection, selector), TimeInterval(SAConnectionCheckBudget.setupMinimum), "no timeout configured still means a finite setup")
        connection.timeout = 2
        XCTAssertEqual(seconds(connection, selector), TimeInterval(SAConnectionCheckBudget.setupMinimum), "a short configured timeout does not shorten setup further")
        connection.timeout = 30
        XCTAssertEqual(seconds(connection, selector), 30, "a longer configured timeout is honoured")
    }

    /// Once setup is through, no deadline is left standing for later statements to report to:
    /// an ordinary query checks its connection and recovers it as before.
    func testNoDeadlineIsLeftStandingAfterSetup() {
        let connection = shortBudgetConnection()
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertTrue(connection.connect())
        XCTAssertNil(connection.value(forKey: "activeSetupDeadline"))

        XCTAssertTrue(connection.reconnect())
        XCTAssertNil(connection.value(forKey: "activeSetupDeadline"))
    }

    /// Without a session there is nothing to arm a deadline on, and nothing is.
    func testWithoutASessionThereIsNoSocketForADeadline() {
        let connection = SPMySQLConnection()
        let selector = #selector(SASetupDeadlineConnection.socketForSetupDeadline)
        typealias Socket = @convention(c) (AnyObject, Selector) -> Int32
        let socket = unsafeBitCast(connection.method(for: selector), to: Socket.self)

        XCTAssertEqual(socket(connection, selector), -1)
    }

    /// Setup that cannot be given a deadline is not run: it would wait with no limit. The connect
    /// fails, closes the session, and says why.
    func testSetupDoesNotRunWithoutADeadline() {
        let connection = SANoSocketForADeadlineConnection()
        connection.useKeepAlive = false
        connection.setupReply = .never
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertFalse(connection.connect())

        XCTAssertNil(connection.setupWaitEndedWith, "no setup statement was run")
        XCTAssertEqual(connection.sessionsClosed, 1)
        XCTAssertFalse(connection.isConnected())
        XCTAssertFalse((connection.lastErrorMessage() ?? "").isEmpty, "the error record says what kept the deadline from being armed")
    }

    /// Initial connect, setup stalled: the connect fails within the budget instead of waiting
    /// for a reply that never comes.
    func testAStalledSetupReplyAtConnectEndsWithinTheBudget() {
        let connection = shortBudgetConnection()
        connection.setupReply = .never
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertFalse(connection.connect())

        XCTAssertEqual(connection.setupWaitEndedWith, 0, "the wait ended as a closed connection")
        XCTAssertGreaterThanOrEqual(connection.setupTook, connection.budget - 0.05)
        XCTAssertLessThan(connection.setupTook, connection.budget + 1.5)
        XCTAssertFalse(connection.isConnected())
        XCTAssertEqual(connection.sessionsClosed, 1, "the session that was lost is closed, not handed on")
    }

    /// The last setup statement can stall as well as the first, and a connect over a session that
    /// is gone says so rather than handing out a session nothing can use.
    func testAStalledLastSetupStatementStillFailsTheConnect() {
        let connection = shortBudgetConnection()
        connection.lastSetupReply = .never
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertFalse(connection.connect())

        XCTAssertEqual(connection.setupWaitEndedWith, 0, "the wait ended as a closed connection")
        XCTAssertGreaterThanOrEqual(connection.setupTook, connection.budget - 0.05)
        XCTAssertLessThan(connection.setupTook, connection.budget + 1.5)
        XCTAssertFalse(connection.isConnected())
        XCTAssertEqual(connection.sessionsClosed, 1, "the session that was lost is closed, not handed on")
    }

    /// A deadline that ran out after the last reply was in has still shut the session down, and
    /// the connect says so rather than handing out a session nothing can use.
    func testADeadlineThatRanOutAfterTheLastReplyStillFailsTheConnect() {
        let connection = shortBudgetConnection()
        connection.lastSetupReply = .doneAfter(connection.budget + 0.3)
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertFalse(connection.connect())

        XCTAssertFalse(connection.isConnected())
        XCTAssertEqual(connection.sessionsClosed, 1, "the session that was shut down is closed, not handed on")
    }

    /// A last setup statement that keeps losing the session ends in the attempts the connection
    /// allows itself without a delegate, not in attempts without end: an attempt that came up and
    /// was lost again in setup counts.
    func testALastSetupStatementThatKeepsFailingDoesNotRetryForever() {
        let connection = shortBudgetConnection()
        connection.budget = 0.2
        connection.lastSetupReply = .never
        connection.stopsStallingAfterHandshakes = 8
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertFalse(connection.reconnect())

        XCTAssertEqual(connection.handshakes, 6, "the attempt, and the five retries the connection decides on by itself")
        XCTAssertFalse(connection.isConnected())
    }

    /// Initial connect, slow but healthy: setup that answers inside the budget is not cut short,
    /// and afterwards the session runs with no limit again.
    func testASlowButHealthySetupAtConnectIsNotCutShort() {
        let connection = shortBudgetConnection()
        connection.setupReply = .after(0.15)
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        XCTAssertTrue(connection.connect())

        XCTAssertEqual(connection.setupWaitEndedWith, 1, "the late reply was read")
        XCTAssertTrue(connection.isConnected())
        XCTAssertEqual(connection.sessionsClosed, 0)
        // Past the budget, the socket still carries a reply: the deadline was lifted with setup.
        Thread.sleep(forTimeInterval: connection.budget + 0.3)
        XCTAssertTrue(connection.theSocketStillCarriesAReply())
    }

    /// A handshake that spent the attempt's budget leaves the connect a second; setup is not held
    /// to that second, but runs on its own budget - here the real one, with no timeout configured.
    func testSetupKeepsItsOwnBudgetWhenTheHandshakeSpentTheAttempts() {
        let connection = SASetupDeadlineConnection()
        connection.useKeepAlive = false
        connection.timeout = 0
        connection.setupReply = .after(1.5)
        defer {
            connection.disconnect()
            connection.closeEverything()
        }

        // What a check-triggered attempt hands the connect once its handshake has spent the budget.
        let attempt = SAConnectionCheckBudget.attemptBudget(forConfiguredTimeout: 0, userEndedWait: false, afterFailedCheck: true)
        let remainder = attempt.remainingConnectTimeout(afterSeconds: 9.9)
        XCTAssertEqual(remainder, 1)

        let selector = #selector(SASetupDeadlineConnection.shakeHands(_:))
        typealias Connect = @convention(c) (AnyObject, Selector, UInt) -> Bool
        let connect = unsafeBitCast(connection.method(for: selector), to: Connect.self)
        XCTAssertTrue(connect(connection, selector, remainder))

        XCTAssertEqual(connection.setupWaitEndedWith, 1, "setup, taking longer than the second that was left, still got its reply")
        XCTAssertGreaterThanOrEqual(connection.setupTook, 1.4)
        XCTAssertTrue(connection.isConnected())
    }

    /// Reconnect, restoration stalled: the reconnect fails within the budget, and the session is
    /// not handed out half restored.
    func testAStalledRestoreAfterReconnectEndsWithinTheBudget() {
        let connection = shortBudgetConnection()
        defer {
            connection.disconnect()
            connection.closeEverything()
        }
        XCTAssertTrue(connection.connect())

        connection.restoreReply = .never
        XCTAssertFalse(connection.reconnect())

        XCTAssertEqual(connection.restoreWaitEndedWith, 0, "the wait ended as a closed connection")
        XCTAssertGreaterThanOrEqual(connection.restoreTook, connection.budget - 0.05)
        XCTAssertLessThan(connection.restoreTook, connection.budget + 1.5)
        XCTAssertFalse(connection.isConnected())
        // The reconnect itself closes a session it could not restore; what matters here is that
        // a restore whose last statement reported nothing wrong is still not taken as restored.
        XCTAssertGreaterThanOrEqual(connection.sessionsClosed, 1)
    }

    /// A restore whose deadline ran out after its last reply was in is not taken as restored.
    func testADeadlineThatRanOutAfterTheRestoreStillFailsTheReconnect() {
        let connection = shortBudgetConnection()
        defer {
            connection.disconnect()
            connection.closeEverything()
        }
        XCTAssertTrue(connection.connect())

        connection.restoreReply = .doneAfter(connection.budget + 0.3)
        XCTAssertFalse(connection.reconnect())

        XCTAssertFalse(connection.isConnected())
    }

    /// Reconnect, restoration slow but healthy: not cut short, and the session runs with no limit afterwards.
    func testASlowButHealthyRestoreAfterReconnectIsNotCutShort() {
        let connection = shortBudgetConnection()
        defer {
            connection.disconnect()
            connection.closeEverything()
        }
        XCTAssertTrue(connection.connect())

        connection.restoreReply = .after(0.15)
        XCTAssertTrue(connection.reconnect())

        XCTAssertEqual(connection.restoreWaitEndedWith, 1, "the late reply was read")
        XCTAssertTrue(connection.isConnected())
        Thread.sleep(forTimeInterval: connection.budget + 0.3)
        XCTAssertTrue(connection.theSocketStillCarriesAReply())
    }
}
