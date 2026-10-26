import XCTest

final class SAClaudeProcessClassifierTests: XCTestCase {
    private func p(_ id: Int64 = 1, user: String = "app", host: String = "10.0.0.5:5555", db: String? = "shop",
                   command: String = "Query", time: Int = 1, state: String? = "executing",
                   info: String? = "SELECT 1") -> SAClaudeProcess {
        SAClaudeProcess(id: id, user: user, host: host, db: db, command: command, time: time, state: state, info: info)
    }
    private typealias C = SAClaudeProcessClassifier

    // MARK: - Groups

    func testLockStatesNeedAttentionRegardlessOfTime() {
        for state in ["Waiting for table metadata lock", "Locked", "waiting for global READ LOCK", "System lock",
                      "Waiting for row lock", "Table lock", "Waiting for lock_wait"] {
            XCTAssertEqual(C.group(p(time: 0, state: state), threshold: 30), .needsAttention, state)
        }
    }

    func testOnlyTheWordLockIsAnImmediateLockWait() {
        for state in ["Sending data", "blocking", "Waiting on clock tick", "unblocked"] {
            XCTAssertEqual(C.group(p(time: 0, state: state), threshold: 30), .running, state)
        }
    }

    func testOtherWaitingForStatesFollowTheThreshold() {
        for state in ["waiting for handler commit", "Waiting for semi-sync ACK from replica", "WAITING FOR TABLE FLUSH",
                      "Waiting for tables", "Waiting for GTID to be committed"] {
            XCTAssertEqual(C.group(p(time: 0, state: state), threshold: 30), .running, state)
            XCTAssertEqual(C.group(p(time: 30, state: state), threshold: 30), .running, state)
            XCTAssertEqual(C.group(p(time: 31, state: state), threshold: 30), .needsAttention, state)
            XCTAssertEqual(C.group(p(time: 11, state: state), threshold: 10), .needsAttention, state)
        }
    }

    func testNonIdleOverThresholdNeedsAttentionUnderRuns() {
        XCTAssertEqual(C.group(p(time: 31), threshold: 30), .needsAttention)
        XCTAssertEqual(C.group(p(time: 30), threshold: 30), .running, "exactly at the threshold is not over it")
        XCTAssertEqual(C.group(p(time: 29), threshold: 30), .running)
        XCTAssertEqual(C.group(p(time: 0, state: nil), threshold: 30), .running)
        XCTAssertEqual(C.group(p(command: "Execute", time: 5000, state: nil), threshold: 30), .needsAttention)
        XCTAssertEqual(C.group(p(command: "Connect", time: 2, state: nil), threshold: 30), .running)
    }

    func testEachThreshold() {
        XCTAssertEqual(C.thresholds, [10, 30, 60, 300])
        XCTAssertEqual(C.defaultThreshold, 30)
        XCTAssertEqual(C.thresholdKey, "ClaudeProcessListAttentionSeconds")
        for t in C.thresholds {
            XCTAssertEqual(C.group(p(time: t), threshold: t), .running, "at \(t)")
            XCTAssertEqual(C.group(p(time: t + 1), threshold: t), .needsAttention, "over \(t)")
            XCTAssertEqual(C.group(p(time: t - 1), threshold: t), .running, "under \(t)")
        }
        XCTAssertEqual(C.group(p(time: 45), threshold: 10), .needsAttention)
        XCTAssertEqual(C.group(p(time: 45), threshold: 60), .running)
    }

    func testSleepIsIdleEvenWithWaitingState() {
        XCTAssertEqual(C.group(p(command: "Sleep", time: 9999, state: nil, info: nil), threshold: 10), .idle)
        XCTAssertEqual(C.group(p(command: "Sleep", time: 5, state: "Waiting for table metadata lock", info: nil), threshold: 10), .idle)
        XCTAssertEqual(C.group(p(command: "sleep", time: 5, state: "Locked", info: nil), threshold: 10), .idle)
        XCTAssertFalse(C.isBackground(p(command: "Sleep", state: nil, info: nil)), "a sleeping client is idle, not background")
    }

    func testBackgroundThreadsNeverNeedAttention() {
        let background: [SAClaudeProcess] = [
            p(command: "Binlog Dump", time: 999_999, state: "Master has sent all binlog to slave; waiting for more updates", info: nil),
            p(command: "Binlog Dump GTID", time: 999_999, state: "Waiting for source to send event", info: nil),
            p(command: "Daemon", time: 999_999, state: "Waiting on empty queue", info: nil),
            p(user: "event_scheduler", command: "Daemon", time: 999_999, state: "Waiting for next activation", info: nil),
            p(user: "system user", command: "Connect", time: 999_999, state: "Waiting for source to send event", info: nil),
            p(user: "system user", command: "Connect", time: 999_999, state: "Slave has read all relay log; waiting for more updates", info: nil),
            p(user: "event_scheduler", command: "Query", time: 999_999, state: "Waiting for table metadata lock", info: nil),
            p(user: "repl", command: "Connect", time: 999_999, state: "Waiting for source to send event", info: nil),
            p(user: "repl", command: "Connect", time: 999_999, state: "Waiting for an event from Coordinator", info: nil),
            p(user: "repl", command: "Connect", time: 999_999, state: "Waiting for master to send event", info: nil),
            p(user: "repl", command: "Connect", time: 999_999, state: "WAITING FOR MASTER TO SEND EVENT", info: nil),
            p(user: "repl", command: "Binlog Dump", time: 0, state: nil, info: nil),
            p(command: "Delayed insert", time: 999_999, state: "Waiting for INSERT", info: nil),
        ]
        for process in background {
            XCTAssertTrue(C.isBackground(process), "\(process.command)/\(process.user)/\(process.state ?? "-")")
            for t in C.thresholds {
                XCTAssertEqual(C.group(process, threshold: t), .idle, "\(process.command)/\(process.user)/\(process.state ?? "-")")
            }
        }
    }

    func testOrdinaryWorkIsNotBackground() {
        XCTAssertFalse(C.isBackground(p()))
        XCTAssertFalse(C.isBackground(p(user: "root", command: "Query", state: "Waiting for table metadata lock")))
        XCTAssertFalse(C.isBackground(p(user: "system", command: "Query")), "only the exact user 'system user'")
        XCTAssertFalse(C.isBackground(p(command: "Query", state: "Sending data", info: "SELECT 'Binlog Dump'")))
    }

    // MARK: - Time text

    func testTimeText() {
        XCTAssertEqual(C.timeText(0), "0s")
        XCTAssertEqual(C.timeText(2), "2s")
        XCTAssertEqual(C.timeText(59), "59s")
        XCTAssertEqual(C.timeText(60), "1m 00s")
        XCTAssertEqual(C.timeText(401), "6m 41s")
        XCTAssertEqual(C.timeText(842), "14m 02s")
        XCTAssertEqual(C.timeText(3599), "59m 59s")
        XCTAssertEqual(C.timeText(3600), "1h 00m")
        XCTAssertEqual(C.timeText(3720), "1h 02m")
        XCTAssertEqual(C.timeText(93_720), "26h 02m")
        XCTAssertEqual(C.timeText(-5), "0s")
    }

    // MARK: - Search

    func testSearchAcrossFieldsCaseInsensitive() {
        let process = p(42, user: "Alice", host: "Web-01:4410", db: "Orders", command: "Query",
                        state: "Sending Data", info: "SELECT * FROM Invoices WHERE total > 5")
        for term in ["alice", "ALICE", "web-01", "orders", "sending data", "from invoices", "invoices", "42"] {
            XCTAssertTrue(C.matches(process, search: term), term)
        }
        XCTAssertFalse(C.matches(process, search: "payments"))
        XCTAssertFalse(C.matches(process, search: "bob"))
    }

    func testSearchEmptyAndNilFields() {
        let bare = p(7, db: nil, command: "Sleep", state: nil, info: nil)
        XCTAssertTrue(C.matches(bare, search: ""))
        XCTAssertTrue(C.matches(bare, search: "   "))
        XCTAssertFalse(C.matches(bare, search: "select"))
        XCTAssertTrue(C.matches(bare, search: "  app  "), "search is trimmed")
    }

    // MARK: - Mine

    func testIsMineByUserIgnoresHost() {
        XCTAssertTrue(C.isMine(p(user: "kunal", host: "1.2.3.4:1"), user: "kunal"))
        XCTAssertTrue(C.isMine(p(user: "kunal", host: "other-host"), user: "kunal"))
        XCTAssertFalse(C.isMine(p(user: "kunal2"), user: "kunal"))
        XCTAssertFalse(C.isMine(p(user: "kunal"), user: ""))
        XCTAssertFalse(C.isMine(p(user: ""), user: ""))
    }

    // MARK: - Sort

    func testSortedGroupsThenLongestFirstThenStableById() {
        let all = [
            p(1, command: "Sleep", time: 500, state: nil, info: nil),
            p(2, time: 5),
            p(3, time: 90),
            p(4, time: 2, state: "Waiting for table metadata lock"),
            p(5, command: "Sleep", time: 900, state: nil, info: nil),
            p(6, time: 40),
            p(7, time: 90),
            p(8, command: "Binlog Dump", time: 100_000, state: nil, info: nil),
            p(9, time: 5),
            p(10, user: "system user", command: "Connect", time: 7_000_000, state: "Waiting for source to send event", info: nil),
        ]
        let ids = C.sorted(all, threshold: 30).map(\.id)
        // needsAttention: 3 (90), 7 (90), 6 (40), 4 (2, lock) | running: 2 (5), 9 (5)
        // idle: sleepers 5 (900), 1 (500), then background 10 (7000000), 8 (100000)
        XCTAssertEqual(ids, [3, 7, 6, 4, 2, 9, 5, 1, 10, 8])
        XCTAssertEqual(C.sorted(all.reversed(), threshold: 30).map(\.id), ids, "input order must not matter")
        XCTAssertEqual(C.sorted([], threshold: 30), [])
    }

    func testSortedFollowsThreshold() {
        let all = [p(1, time: 20), p(2, time: 5)]
        XCTAssertEqual(C.sorted(all, threshold: 30).map(\.id), [1, 2])
        XCTAssertEqual(C.sorted([p(1, time: 5), p(2, time: 20)], threshold: 10).map(\.id), [2, 1])
    }

    // MARK: - Row parsing

    func testRowParsingTypedValues() throws {
        let row: [String: Any] = ["Id": NSNumber(value: 4812), "User": "kunal", "Host": "localhost:5000", "db": "shop",
                                  "Command": "Query", "Time": NSNumber(value: 14), "State": "executing", "Info": "SELECT 1"]
        let parsed = try XCTUnwrap(SAClaudeProcess(row: row))
        XCTAssertEqual(parsed, SAClaudeProcess(id: 4812, user: "kunal", host: "localhost:5000", db: "shop",
                                               command: "Query", time: 14, state: "executing", info: "SELECT 1"))
    }

    func testRowParsingNSNullAndStringNumbersAndCase() throws {
        let row: [String: Any] = ["ID": "99", "user": "u", "HOST": "h", "DB": NSNull(), "command": "Sleep",
                                  "TIME": "12", "state": NSNull(), "INFO": NSNull()]
        let parsed = try XCTUnwrap(SAClaudeProcess(row: row))
        XCTAssertEqual(parsed.id, 99)
        XCTAssertEqual(parsed.time, 12)
        XCTAssertNil(parsed.db)
        XCTAssertNil(parsed.state)
        XCTAssertNil(parsed.info)
        XCTAssertEqual(parsed.command, "Sleep")
    }

    func testRowParsingMissingOrBadFields() throws {
        XCTAssertNil(SAClaudeProcess(row: [:]), "no id")
        XCTAssertNil(SAClaudeProcess(row: ["Id": NSNull(), "User": "u"]))
        XCTAssertNil(SAClaudeProcess(row: ["Id": "abc"]))
        let sparse = try XCTUnwrap(SAClaudeProcess(row: ["Id": 5]))
        XCTAssertEqual(sparse.user, "")
        XCTAssertEqual(sparse.host, "")
        XCTAssertEqual(sparse.command, "")
        XCTAssertEqual(sparse.time, 0)
        let nullTime = try XCTUnwrap(SAClaudeProcess(row: ["Id": 5, "Time": NSNull()]))
        XCTAssertEqual(nullTime.time, 0)
        let negative = try XCTUnwrap(SAClaudeProcess(row: ["Id": 5, "Time": -3]))
        XCTAssertEqual(negative.time, 0)
        let big = try XCTUnwrap(SAClaudeProcess(row: ["Id": NSNumber(value: Int64(5_000_000_000)), "Time": "7.9"]))
        XCTAssertEqual(big.id, 5_000_000_000)
        XCTAssertEqual(big.time, 7)
    }

    func testRowParsingDecimalAndLargeTimeAndMariaDBColumns() throws {
        let decimal = try XCTUnwrap(SAClaudeProcess(row: ["Id": NSDecimalNumber(string: "17"), "Time": NSDecimalNumber(string: "12.7")]))
        XCTAssertEqual(decimal.id, 17)
        XCTAssertEqual(decimal.time, 12)
        let huge = try XCTUnwrap(SAClaudeProcess(row: ["Id": 1, "Time": NSNumber(value: Int64(Int32.max) + 10)]))
        XCTAssertEqual(huge.time, Int(Int32.max) + 10)
        let maria: [String: Any] = ["Id": NSNumber(value: 8), "User": "app", "Host": "h:1", "db": "d", "Command": "Query",
                                    "Time": NSNumber(value: 3), "State": "Sending data", "Info": "SELECT 1",
                                    "Stage": NSNumber(value: 1), "Max_stage": NSNumber(value: 2), "Progress": "12.500",
                                    "Memory_used": NSNumber(value: 123456), "Max_memory_used": NSNumber(value: 234567),
                                    "Examined_rows": NSNumber(value: 0), "Query_id": NSNumber(value: 99), "Info_binary": NSNull(), "TID": NSNumber(value: 4321)]
        XCTAssertEqual(SAClaudeProcess(row: maria),
                       SAClaudeProcess(id: 8, user: "app", host: "h:1", db: "d", command: "Query", time: 3, state: "Sending data", info: "SELECT 1"))
    }

    func testRowParsingAcceptsTheControllersRowShape() throws {
        // SPProcessListController hands back NSDictionary rows with NSNumber Id/Time and NSNull for missing text.
        let row = NSMutableDictionary()
        row["Id"] = NSNumber(value: 3)
        row["User"] = "root"
        row["Host"] = "localhost"
        row["db"] = NSNull()
        row["Command"] = "Sleep"
        row["Time"] = NSNumber(value: 0)
        row["State"] = ""
        row["Info"] = NSNull()
        row["Progress"] = "0.000"
        let parsed = try XCTUnwrap(SAClaudeProcess(row: row as? [String: Any] ?? [:]))
        XCTAssertEqual(parsed.id, 3)
        XCTAssertNil(parsed.db)
        XCTAssertEqual(parsed.state, "")
    }
}
