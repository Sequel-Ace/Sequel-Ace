import XCTest

final class SAForeignKeyReferenceRuleSupportTests: XCTestCase {
    func testStandardReferenceRulesRespectServerCapabilities() {
        XCTAssertFalse(SAForeignKeyReferenceRuleSupport.requiresStandardForeignKeyReferences(isMariaDB: true, serverVersionIsAtLeast84: true, restrictionQueryErrored: false, restrictionValue: "ON"))
        XCTAssertFalse(SAForeignKeyReferenceRuleSupport.requiresStandardForeignKeyReferences(isMariaDB: false, serverVersionIsAtLeast84: false, restrictionQueryErrored: false, restrictionValue: "ON"))
        XCTAssertTrue(SAForeignKeyReferenceRuleSupport.requiresStandardForeignKeyReferences(isMariaDB: false, serverVersionIsAtLeast84: true, restrictionQueryErrored: true, restrictionValue: nil))
    }

    func testRestrictionValueDisablesStandardReferenceRulesForFalseLikeValues() {
        XCTAssertFalse(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences("0"))
        XCTAssertFalse(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences(0))
        XCTAssertFalse(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences(" off "))
        XCTAssertFalse(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences("FALSE"))
    }

    func testRestrictionValueDefaultsToEnabled() {
        XCTAssertTrue(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences(nil))
        XCTAssertTrue(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences(NSNull()))
        XCTAssertTrue(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences("1"))
        XCTAssertTrue(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences("ON"))
        XCTAssertTrue(SAForeignKeyReferenceRuleSupport.restrictionEnforcesStandardReferences("TRUE"))
    }

    func testSingleColumnUniqueReferenceColumnsIncludesPrimaryAndUniqueColumns() {
        let columns = uniqueColumns(from: [
            ["Non_unique": "0", "Key_name": "PRIMARY", "Column_name": "id", "Sub_part": NSNull()],
            ["Non_unique": 0, "Key_name": "uniq_email", "Column_name": "email", "Sub_part": ""],
            ["Non_unique": "1", "Key_name": "idx_name", "Column_name": "name", "Sub_part": NSNull()]
        ])

        XCTAssertEqual(columns, ["id", "email"])
    }

    func testSingleColumnUniqueReferenceColumnsRejectsCompositeAndPrefixIndexes() {
        let columns = uniqueColumns(from: [
            ["Non_unique": "0", "Key_name": "uniq_name_locale", "Column_name": "name", "Sub_part": NSNull()],
            ["Non_unique": "0", "Key_name": "uniq_name_locale", "Column_name": "locale", "Sub_part": NSNull()],
            ["Non_unique": "0", "Key_name": "uniq_prefix", "Column_name": "slug", "Sub_part": "16"],
            ["Non_unique": "0", "Key_name": "", "Column_name": "missing_key_name", "Sub_part": NSNull()],
            ["Non_unique": "0", "Key_name": "uniq_missing_column", "Column_name": "", "Sub_part": NSNull()]
        ])

        XCTAssertTrue(columns.isEmpty)
    }

    private func uniqueColumns(from rows: [[String: Any]]) -> Set<String> {
        let indexRows = rows.map { $0 as NSDictionary } as NSArray
        let columns = SAForeignKeyReferenceRuleSupport.singleColumnUniqueReferenceColumns(indexRows)

        return Set(columns.compactMap { $0 as? String })
    }
}

final class SAFieldRemovalTaskTests: XCTestCase {
    func testSuccessfulRemovalRunsBothQueriesThenRefreshes() {
        let task = makeTask()
        var events: [String] = []

        task.run(
            foreignKeyQuery: {
                events.append("foreign key query")
                return .succeeded
            },
            fieldQuery: {
                events.append("field query")
                return .succeeded
            },
            foreignKeyFailure: {
                XCTFail("A successful foreign-key query must not report a failure")
            },
            fieldFailure: {
                XCTFail("A successful field query must not report a failure")
            },
            schemaRefresh: {
                events.append("schema refresh")
            },
            completion: {
                events.append("completion")
            }
        )

        XCTAssertEqual(events, [
            "foreign key query",
            "field query",
            "schema refresh",
            "completion"
        ])
    }

    func testFailuresAdvanceInOrderWithoutRefreshing() {
        let task = makeTask()
        var events: [String] = []

        task.run(
            foreignKeyQuery: {
                events.append("foreign key query")
                return .failed
            },
            fieldQuery: {
                events.append("field query")
                return .failed
            },
            foreignKeyFailure: {
                events.append("foreign key failure")
            },
            fieldFailure: {
                events.append("field failure")
            },
            schemaRefresh: {
                XCTFail("Failed queries must not refresh schema state")
            },
            completion: {
                events.append("completion")
            }
        )

        XCTAssertEqual(events, [
            "foreign key query",
            "foreign key failure",
            "field query",
            "field failure",
            "completion"
        ])
    }

    func testCancellationBeforeAdmissionSkipsQueries() {
        let task = makeTask()
        var didComplete = false

        task.cancel()
        task.run(
            foreignKeyQuery: {
                XCTFail("Cancellation must prevent foreign-key query admission")
                return .failed
            },
            fieldQuery: {
                XCTFail("Cancellation must prevent field query admission")
                return .failed
            },
            foreignKeyFailure: {
                XCTFail("A skipped foreign-key query must not report a failure")
            },
            fieldFailure: {
                XCTFail("A skipped field query must not report a failure")
            },
            schemaRefresh: {
                XCTFail("No schema refresh is needed when no query was admitted")
            },
            completion: {
                didComplete = true
            }
        )

        XCTAssertTrue(didComplete)
    }

    func testCancelledForeignKeyQuerySkipsFieldAndRefreshesPossibleChanges() {
        let task = makeTask()
        var events: [String] = []

        task.run(
            foreignKeyQuery: {
                events.append("foreign key query")
                return .cancelled
            },
            fieldQuery: {
                XCTFail("A cancelled foreign-key query must prevent the field query")
                return .failed
            },
            foreignKeyFailure: {
                XCTFail("Cancellation must not be reported as a query failure")
            },
            fieldFailure: {
                XCTFail("The skipped field query must not report a failure")
            },
            schemaRefresh: {
                events.append("schema refresh")
            },
            completion: {
                events.append("completion")
            }
        )

        XCTAssertEqual(events, [
            "foreign key query",
            "schema refresh",
            "completion"
        ])
    }

    func testAdmittedQueryCancellationRunsOffMainAndCannotReachRefreshQuery() {
        let task = makeTask(foreignKeyName: nil)
        let queryStarted = expectation(description: "field query started")
        let cancellationAttempted = expectation(description: "query cancellation attempted")
        let taskCompleted = expectation(description: "field removal task completed")
        let cancellationAfterRefresh = expectation(description: "no cancellation after schema refresh")
        cancellationAfterRefresh.isInverted = true

        let allowQueryToFinish = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var refreshStarted = false
        var cancellationWasReported = false

        DispatchQueue.global(qos: .userInitiated).async {
            task.run(
                foreignKeyQuery: {
                    XCTFail("A task without a foreign key must skip that query")
                    return .failed
                },
                fieldQuery: {
                    queryStarted.fulfill()
                    allowQueryToFinish.wait()
                    return .cancelled
                },
                foreignKeyFailure: {
                    XCTFail("A skipped foreign-key query must not report a failure")
                },
                fieldFailure: {
                    XCTFail("Cancellation must not be reported as a field failure")
                },
                schemaRefresh: {
                    stateLock.lock()
                    refreshStarted = true
                    stateLock.unlock()
                },
                completion: {
                    XCTAssertTrue(Thread.isMainThread)
                    taskCompleted.fulfill()
                }
            )
        }

        wait(for: [queryStarted], timeout: 2)
        task.cancel()
        task.requestQueryCancellation {
            XCTAssertFalse(Thread.isMainThread)

            stateLock.lock()
            let didStartRefresh = refreshStarted
            let shouldReportFirstAttempt = !cancellationWasReported
            cancellationWasReported = true
            stateLock.unlock()

            if didStartRefresh {
                cancellationAfterRefresh.fulfill()
            }
            if shouldReportFirstAttempt {
                cancellationAttempted.fulfill()
                allowQueryToFinish.signal()
            }
        }

        wait(for: [cancellationAttempted, taskCompleted], timeout: 2)
        wait(for: [cancellationAfterRefresh], timeout: 0.1)
    }

    private func makeTask(foreignKeyName: String? = "fk_child_parent") -> SAFieldRemovalTask {
        SAFieldRemovalTask(
            field: "parent_id",
            foreignKeyName: foreignKeyName,
            table: "child",
            database: "test"
        )
    }
}
