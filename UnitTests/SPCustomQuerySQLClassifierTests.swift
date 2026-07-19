//
//  SPCustomQuerySQLClassifierTests.swift
//  Unit Tests
//

import XCTest
import SPMySQL

final class SPCustomQuerySQLClassifierTests: XCTestCase {

    func testExplainableAcceptsOnlySelectAndWith() {
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("SELECT * FROM t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("(WITH cte AS (SELECT 1) SELECT * FROM cte)"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("WITH RECURSIVE cte AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM cte WHERE n < 10) SELECT * FROM cte"))
        // Lowercase / mixed-case keywords must still classify as explainable
        // because the classifier uppercases the trimmed prefix before matching.
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("select * from t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("(with cte as (select 1) select * from cte)"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("EXPLAIN SELECT * FROM t"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("UPDATE t SET c = 1"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("SELECTOR_TABLE"))
    }

    func testPlainExplainPlanInspectionIsSafe() {
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN SELECT * FROM t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN FORMAT=JSON UPDATE t SET c = 1"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("DESCRIBE t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("DESC t"))
        // Lowercase keyword variants must use the same safe-without-warning rule.
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("explain select * from t"))
    }

    func testExplainAnalyzeReadOnlyStatementsAreSafe() {
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN ANALYZE SELECT * FROM t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN ANALYZE TABLE t"))
        // Note: `EXPLAIN ANALYZE WITH ...` is conservatively treated as
        // destructive even when the outer verb is SELECT, see
        // `testExplainAnalyzeWithCTERequiresWarning`.
    }

    func testExplainAnalyzeMutatingStatementsRequireWarning() {
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN ANALYZE DELETE FROM t WHERE id = 1"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN ANALYZE UPDATE t SET c = c + 1"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN ANALYZE FORMAT=TREE DELETE FROM t WHERE id = 1"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN FORMAT=TREE ANALYZE UPDATE t SET c = 1"))
        // Lowercase EXPLAIN ANALYZE on a mutating statement must still warn.
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("explain analyze delete from t where id = 1"))
    }

    func testExplainAliasesUseTheSameAnalyzeSafetyRule() {
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("DESCRIBE ANALYZE DELETE FROM t WHERE id = 1"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("DESC ANALYZE UPDATE t SET c = 1"))
    }

    func testCommentsAreIgnoredButKeywordBoundariesRemainStrict() {
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("/* c */ EXPLAIN /* c */ ANALYZE /* c */ DELETE FROM t"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAINER ANALYZE DELETE FROM t"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("SELECTOR_TABLE"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("SELECT/* c */1"))
        XCTAssertEqual(
            SPCustomQuerySQLClassifier.stripSQLComments("SELECT '-- value', `db#name`, \"/* value */\""),
            "SELECT '-- value', `db#name`, \"/* value */\""
        )
        XCTAssertEqual(
            SPCustomQuerySQLClassifier.stripSQLComments("/*!40101 USE executable_db */").trimmingCharacters(in: .whitespacesAndNewlines),
            "USE executable_db"
        )
        XCTAssertFalse(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("/*! EXPLAIN ANALYZE DELETE FROM t */")
        )
        XCTAssertFalse(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("/*!99999 DELETE FROM future_table */")
        )
        XCTAssertEqual(
            SPCustomQuerySQLClassifier.stripSQLComments("SELECT 1--"),
            "SELECT 1 "
        )
    }

    func testUnknownExecutableCommentGatesAlwaysRequireWarning() {
        // On current servers the future-gated SELECT is ignored, so the DELETE
        // is the real leading statement. Preserving only the comment body would
        // incorrectly classify this as a safe SELECT.
        XCTAssertFalse(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
                "/*!99999 SELECT */ DELETE FROM important_table"
            )
        )

        // The inverse interpretation must also be considered: ignoring a gated
        // destructive body is not safe when an unknown server may execute it.
        XCTAssertFalse(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
                "/*!99999 DELETE FROM important_table */ SELECT 1"
            )
        )

        // Even when both visible forms are reads, unknown gates are rejected
        // instead of guessing which SQL token stream the server will execute.
        let futureRead = "/*!99999 SELECT 1 */ SELECT 2"
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(futureRead))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable(futureRead))

        // Supplying server context removes the ambiguity and retains the
        // existing behavior for known inactive gates.
        XCTAssertTrue(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
                futureRead,
                serverVersion: 80_000,
                serverIsMariaDB: false
            )
        )

        // MariaDB-only executable comments are also indeterminate when the
        // caller has not supplied the server flavor.
        XCTAssertFalse(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
                "/*M! SELECT 1 */ SELECT 2"
            )
        )

        // Gate-looking text inside a string is data, not an executable comment.
        XCTAssertTrue(
            SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
                "SELECT '/*!99999 DELETE FROM important_table */'"
            )
        )
    }

    func testLeadingParenthesesAreUnwrappedConsistentlyWithExplainable() {
        // Matches isQueryExplainable's leading-`(` stripping so the destructive
        // gate and the manual Explain menu share the same view of wrapped
        // statements.
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("(SELECT * FROM t)"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("((SELECT 1))"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("(EXPLAIN ANALYZE DELETE FROM t WHERE id = 1)"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("(UPDATE t SET c = 1)"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("(EXPLAIN FORMAT=TREE ANALYZE UPDATE t SET c = 1)"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("((DESC ANALYZE DELETE FROM t WHERE id = 1))"))
    }

    func testExplainAnalyzeWithCTERequiresWarning() {
        // `EXPLAIN ANALYZE WITH ...` is conservatively treated as destructive
        // because MySQL allows CTEs to introduce UPDATE/DELETE statements that
        // would actually mutate data when executed under `EXPLAIN ANALYZE`.
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "EXPLAIN ANALYZE WITH c AS (SELECT 1 AS id) UPDATE t JOIN c ON t.id = c.id SET t.c = 1"
        ))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "EXPLAIN ANALYZE FORMAT=TREE WITH c AS (SELECT 1 AS id) DELETE t FROM t JOIN c ON t.id = c.id"
        ))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "DESCRIBE ANALYZE WITH c AS (SELECT 1) UPDATE t SET c = 1"
        ))
        // Read-only CTE SELECT under EXPLAIN ANALYZE is also treated as
        // destructive (conservative false positive — safer to warn than to
        // silently run mutations).
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "EXPLAIN ANALYZE WITH c AS (SELECT 1) SELECT * FROM c"
        ))
        // Plain `EXPLAIN WITH ...` (no ANALYZE) is still safe because plain
        // EXPLAIN does not execute the statement.
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "EXPLAIN WITH c AS (SELECT 1) UPDATE t SET c = 1"
        ))
        // Comments between ANALYZE and WITH still trigger the guard because
        // stripSQLComments runs before tokenization.
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "EXPLAIN ANALYZE /* hint */ WITH c AS (SELECT 1) UPDATE t SET c = 1"
        ))
        // EXTENDED/PARTITIONS modifiers before WITH must not bypass the guard.
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(
            "EXPLAIN ANALYZE EXTENDED WITH c AS (SELECT 1) UPDATE t SET c = 1"
        ))
    }

    func testEmptyAndIrregularWhitespaceInputs() {
        // Empty / whitespace-only inputs are never explainable and never safe.
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable(""))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("   "))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(""))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("   "))
        // Multiple spaces and tabs between keywords must tokenize identically
        // to a single space (sqlTokens splits on any whitespace scalar).
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN    SELECT  *  FROM  t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN\t\tSELECT * FROM t"))
    }

    func testDatabaseContextTracksUseStatementsWithCommentsAndQuotedNames() {
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "USE new_db; -- selected\n", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "new_db"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "/* before */ USE `new``db/*literal*/#name` /* after */", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "new`db/*literal*/#name"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "USE hash_db # selected", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "hash_db"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "USE \"new\"\"db/*literal*/\"", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "new\"db/*literal*/"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "USE`quoted_db`", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "quoted_db"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "USEFUL db", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "old_db"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "/*!40101 USE versioned_db */", currentDatabase: "old_db", databaseNamesAreCaseSensitive: true),
            "versioned_db"
        )
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "/*M!100100 USE maria_db */",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true,
                serverVersion: 101_100,
                serverIsMariaDB: true
            ),
            "maria_db"
        )
    }

    func testDatabaseContextHonorsExecutableCommentVersionAndServerFlavor() {
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "/*!99999 USE future_db */",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true
            ),
            "old_db"
        )
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "/*M!100100 USE maria_db */",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true
            ),
            "old_db"
        )
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "/*!80000 USE mysql_only_db */",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true,
                serverVersion: 101_100,
                serverIsMariaDB: true
            ),
            "old_db"
        )
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "/*!40101 USE shared_db */",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true,
                serverVersion: 101_100,
                serverIsMariaDB: true
            ),
            "shared_db"
        )
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "/*!999999999999999999999999 USE overflow_db */",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true
            ),
            "old_db"
        )
    }

    func testDatabaseContextClearsOnlyWhenDroppedNameMatchesUnderServerCaseRules() {
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE `app_db`", currentDatabase: "app_db", databaseNamesAreCaseSensitive: true)
        )
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "DROP SCHEMA IF EXISTS app_db; -- rebuild", currentDatabase: "app_db", databaseNamesAreCaseSensitive: true)
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE reporting", currentDatabase: "app_db", databaseNamesAreCaseSensitive: false),
            "app_db"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE app_db_backup", currentDatabase: "app_db", databaseNamesAreCaseSensitive: false),
            "app_db"
        )
        XCTAssertEqual(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE app_db", currentDatabase: "App_DB", databaseNamesAreCaseSensitive: true),
            "App_DB"
        )
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE app_db", currentDatabase: "App_DB", databaseNamesAreCaseSensitive: false)
        )
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "/*! DROP DATABASE App_DB */", currentDatabase: "App_DB", databaseNamesAreCaseSensitive: true)
        )
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE \"App_\"\"DB\"", currentDatabase: "App_\"DB", databaseNamesAreCaseSensitive: true)
        )
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE`app_db`", currentDatabase: "app_db", databaseNamesAreCaseSensitive: true)
        )
        XCTAssertNil(
            contextDatabaseName(afterSuccessfulQuery: "DROP DATABASE IF EXISTS`app_db`", currentDatabase: "app_db", databaseNamesAreCaseSensitive: true)
        )
    }

    func testCaseSensitivityLookupIsRequiredOnlyForCaseAmbiguousDrops() {
        for query in [
            "SHOW WARNINGS",
            "SELECT ROW_COUNT()",
            "SELECT FOUND_ROWS()",
            "USE app_db",
            "DROP DATABASE app_db",
            "DROP DATABASE reporting"
        ] {
            XCTAssertFalse(
                requiresCaseSensitivityLookup(for: query, currentDatabase: "app_db"),
                query
            )
        }

        XCTAssertFalse(
            requiresCaseSensitivityLookup(for: "DROP DATABASE app_db", currentDatabase: nil)
        )
        XCTAssertTrue(
            requiresCaseSensitivityLookup(for: "DROP DATABASE app_db", currentDatabase: "App_DB")
        )
        XCTAssertTrue(
            requiresCaseSensitivityLookup(
                for: "/*!80000 DROP SCHEMA IF EXISTS `app_db` */",
                currentDatabase: "App_DB"
            )
        )
        XCTAssertFalse(
            requiresCaseSensitivityLookup(
                for: "/*!99999 DROP DATABASE app_db */",
                currentDatabase: "App_DB"
            )
        )
    }

    func testDatabaseContextTracksCustomQueryAndImportBatchSequence() {
        var databaseName: String? = "app_db"

        databaseName = contextDatabaseName(
            afterSuccessfulQuery: "INSERT INTO events VALUES (1)",
            currentDatabase: databaseName,
            databaseNamesAreCaseSensitive: true
        )
        XCTAssertEqual(databaseName, "app_db")

        databaseName = contextDatabaseName(
            afterSuccessfulQuery: "DROP DATABASE app_db",
            currentDatabase: databaseName,
            databaseNamesAreCaseSensitive: true
        )
        XCTAssertNil(databaseName)

        databaseName = contextDatabaseName(
            afterSuccessfulQuery: "CREATE DATABASE app_db",
            currentDatabase: databaseName,
            databaseNamesAreCaseSensitive: true
        )
        XCTAssertNil(databaseName)

        databaseName = contextDatabaseName(
            afterSuccessfulQuery: "USE app_db; /* restored */",
            currentDatabase: databaseName,
            databaseNamesAreCaseSensitive: true
        )
        XCTAssertEqual(databaseName, "app_db")
    }

    func testDatabaseContextPrefixGuardSkipsOrdinaryStatements() {
        for query in [
            "INSERT INTO t VALUES (1)",
            "UPDATE t SET value = 1",
            "DELETE FROM t",
            "SELECT 1",
            "USEFUL identifier",
            "DROPLET identifier"
        ] {
            XCTAssertFalse(SASQLDatabaseContext.queryCouldChangeDatabaseContext(query), query)
        }

        for query in [
            "USE target",
            " use target",
            "DROP DATABASE target",
            "drop schema target",
            "# comment\nUSE target",
            "-- comment\nUSE target",
            "/* comment */ USE target"
        ] {
            XCTAssertTrue(SASQLDatabaseContext.queryCouldChangeDatabaseContext(query), query)
        }
    }

    func testMariaDBDoesNotTreatBracketsAsQuotedIdentifiers() {
        XCTAssertEqual(
            SPCustomQuerySQLClassifier.stripSQLComments(
                "SELECT [/* comment */]",
                serverVersion: 101_100,
                serverIsMariaDB: true
            ),
            "SELECT [ ]"
        )
        XCTAssertEqual(
            contextDatabaseName(
                afterSuccessfulQuery: "USE [new database]",
                currentDatabase: "old_db",
                databaseNamesAreCaseSensitive: true,
                serverVersion: 101_100,
                serverIsMariaDB: true
            ),
            "old_db"
        )
    }

    func testDatabaseContextDetectsSelectionAndDeselectionTransitions() {
        XCTAssertFalse(SASQLDatabaseContext.databaseNameChanged(from: nil, to: nil))
        XCTAssertFalse(SASQLDatabaseContext.databaseNameChanged(from: "app_db", to: "app_db"))
        XCTAssertTrue(SASQLDatabaseContext.databaseNameChanged(from: nil, to: "app_db"))
        XCTAssertTrue(SASQLDatabaseContext.databaseNameChanged(from: "app_db", to: nil))
        XCTAssertTrue(SASQLDatabaseContext.databaseNameChanged(from: "app_db", to: "reporting"))
    }

    private func contextDatabaseName(
        afterSuccessfulQuery query: String,
        currentDatabase: String?,
        databaseNamesAreCaseSensitive: Bool,
        serverVersion: Int = 80_000,
        serverIsMariaDB: Bool = false
    ) -> String? {
        SASQLDatabaseContext.databaseName(
            afterSuccessfulQuery: query,
            currentDatabase: currentDatabase,
            databaseNamesAreCaseSensitive: databaseNamesAreCaseSensitive,
            serverVersion: serverVersion,
            serverIsMariaDB: serverIsMariaDB
        )
    }

    private func requiresCaseSensitivityLookup(
        for query: String,
        currentDatabase: String?,
        serverVersion: Int = 80_000,
        serverIsMariaDB: Bool = false
    ) -> Bool {
        SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(
            for: query,
            currentDatabase: currentDatabase,
            serverVersion: serverVersion,
            serverIsMariaDB: serverIsMariaDB
        )
    }
}

final class SASQLDatabaseContextIntegrationTests: XCTestCase {

    func testLiveDeferredCaseSensitivityLookupPreservesDiagnosticsAcrossCustomQueryActions() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("No local MySQL connection configured for the diagnostic-preservation regression.")
        }
        guard connection.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable for the diagnostic-preservation regression.")
        }

        let identifier = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let database = "sa_diagnostics_\(identifier)"

        defer {
            _ = connection.queryString("DROP DATABASE IF EXISTS \(backtickQuoted(database))")
            connection.disconnect()
        }

        _ = connection.queryString("CREATE DATABASE \(backtickQuoted(database))")
        assertQuerySucceeded(connection)
        _ = connection.queryString(
            "CREATE TABLE diagnostics (id INT PRIMARY KEY, value INT)",
            assertingDatabase: database
        )
        assertQuerySucceeded(connection)
        _ = connection.queryString(
            "INSERT INTO diagnostics VALUES (1, 0)",
            assertingDatabase: database
        )
        assertQuerySucceeded(connection)

        _ = connection.queryString(
            "UPDATE diagnostics SET value = value + 1 WHERE id = 1",
            assertingDatabase: database
        )
        assertQuerySucceeded(connection)
        XCTAssertFalse(
            SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(
                for: "SELECT ROW_COUNT()",
                currentDatabase: database,
                serverVersion: 80_000,
                serverIsMariaDB: false
            )
        )
        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT ROW_COUNT()", assertingDatabase: database) as? String,
            "1"
        )
        assertQuerySucceeded(connection)

        _ = connection.queryString(
            "SELECT SQL_CALC_FOUND_ROWS value FROM diagnostics UNION ALL SELECT 2 UNION ALL SELECT 3 LIMIT 1",
            assertingDatabase: database
        )
        assertQuerySucceeded(connection)
        XCTAssertFalse(
            SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(
                for: "SELECT FOUND_ROWS()",
                currentDatabase: database,
                serverVersion: 80_000,
                serverIsMariaDB: false
            )
        )
        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT FOUND_ROWS()", assertingDatabase: database) as? String,
            "3"
        )
        assertQuerySucceeded(connection)

        _ = connection.queryString(
            "DROP TABLE IF EXISTS missing_diagnostics_table",
            assertingDatabase: database
        )
        assertQuerySucceeded(connection)
        XCTAssertFalse(
            SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(
                for: "SHOW WARNINGS",
                currentDatabase: database,
                serverVersion: 80_000,
                serverIsMariaDB: false
            )
        )
        let warningsResult = connection.queryString("SHOW WARNINGS", assertingDatabase: database)
        assertQuerySucceeded(connection)
        XCTAssertGreaterThan(warningsResult?.numberOfRows() ?? 0, 0)
    }

    func testLiveCustomQueryBatchFollowsSuccessfulUse() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("No local MySQL connection configured for the custom-query batch regression.")
        }
        guard connection.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable for the custom-query batch regression.")
        }

        let identifier = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let databaseA = "sa_batch_\(identifier)_a"
        let databaseB = "sa_batch_\(identifier)_b"
        let databases = [databaseA, databaseB]

        defer {
            for database in databases {
                _ = connection.queryString("DROP DATABASE IF EXISTS \(backtickQuoted(database))")
            }
            connection.disconnect()
        }

        for database in databases {
            _ = connection.queryString("CREATE DATABASE \(backtickQuoted(database))")
            assertQuerySucceeded(connection)
        }

        // Mirror SPCustomQuery.performQueriesTask: each statement is asserted
        // against the context derived from the preceding successful statement.
        var databaseName: String? = databaseA
        let queries = [
            "CREATE TABLE before_use (value INT)",
            "USE \(backtickQuoted(databaseB))",
            "CREATE TABLE after_use (value INT)",
            "INSERT INTO after_use VALUES (1)"
        ]

        for query in queries {
            _ = connection.queryString(query, assertingDatabaseContext: databaseName)
            assertQuerySucceeded(connection)
            databaseName = SASQLDatabaseContext.databaseName(
                afterSuccessfulQuery: query,
                currentDatabase: databaseName,
                databaseNamesAreCaseSensitive: true,
                serverVersion: 80_000,
                serverIsMariaDB: false
            )
        }

        XCTAssertEqual(databaseName, databaseB)
        XCTAssertEqual(
            connection.getFirstField(
                fromQuery: "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'after_use'",
                assertingDatabase: databaseA
            ) as? String,
            "0"
        )
        XCTAssertEqual(
            connection.getFirstField(
                fromQuery: "SELECT COUNT(*) FROM after_use",
                assertingDatabase: databaseB
            ) as? String,
            "1"
        )
    }

    func testLiveCrossDatabaseViewCopyUsesTargetContext() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("No local MySQL connection configured for the cross-database view-copy regression.")
        }
        guard connection.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable for the cross-database view-copy regression.")
        }

        let identifier = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let sourceDatabase = "sa_view_\(identifier)_source"
        let targetDatabase = "sa_view_\(identifier)_target"
        let databases = [sourceDatabase, targetDatabase]

        defer {
            for database in databases {
                _ = connection.queryString("DROP DATABASE IF EXISTS \(backtickQuoted(database))")
            }
            connection.disconnect()
        }

        for database in databases {
            _ = connection.queryString("CREATE DATABASE \(backtickQuoted(database))")
            assertQuerySucceeded(connection)
            _ = connection.queryString("CREATE TABLE items (value INT)", assertingDatabase: database)
            assertQuerySucceeded(connection)
        }
        _ = connection.queryString("INSERT INTO items VALUES (1)", assertingDatabase: sourceDatabase)
        assertQuerySucceeded(connection)
        _ = connection.queryString("INSERT INTO items VALUES (2)", assertingDatabase: targetDatabase)
        assertQuerySucceeded(connection)
        _ = connection.queryString("CREATE VIEW source_view AS SELECT value FROM items", assertingDatabase: sourceDatabase)
        assertQuerySucceeded(connection)

        let createResult = connection.queryString("SHOW CREATE VIEW source_view", assertingDatabase: sourceDatabase)
        assertQuerySucceeded(connection)
        let createRow = try XCTUnwrap(createResult?.getRowAsArray() as? [Any])
        let createStatement = try XCTUnwrap(createRow.count > 1 ? createRow[1] as? String : nil)
        let bodyRange = try XCTUnwrap(createStatement.range(of: " AS "))
        let viewBody = String(createStatement[bodyRange.lowerBound...])

        // Mirror SPTablesList._copyTable's view branch: SHOW CREATE's body is
        // unqualified, so asserting the target database is what binds it to
        // the target's tables and creates the view in the requested schema.
        _ = connection.queryString(
            "CREATE VIEW copied_view \(viewBody)",
            assertingDatabase: targetDatabase
        )
        assertQuerySucceeded(connection)

        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT value FROM copied_view", assertingDatabase: targetDatabase) as? String,
            "2"
        )
        XCTAssertEqual(
            connection.getFirstField(
                fromQuery: "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = DATABASE() AND table_name = 'copied_view'",
                assertingDatabase: sourceDatabase
            ) as? String,
            "0"
        )
    }

    private func newLocalConnection() -> SPMySQLConnection? {
        let environment = ProcessInfo.processInfo.environment
        var socketPath = environment["SPMYSQL_TEST_SOCKET"]
        let testHost = environment["SPMYSQL_TEST_HOST"]

        if (socketPath?.isEmpty ?? true), (testHost?.isEmpty ?? true) {
            socketPath = ["/tmp/mysql.sock", "/opt/homebrew/var/mysql/mysql.sock"]
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }

        let connection = SPMySQLConnection()
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false

        if let testHost, !testHost.isEmpty {
            connection.useSocket = false
            connection.host = testHost
            if let port = environment["SPMYSQL_TEST_PORT"].flatMap(UInt.init) {
                connection.port = port
            }
        } else if let socketPath, !socketPath.isEmpty {
            connection.useSocket = true
            connection.socketPath = socketPath
        } else {
            return nil
        }

        return connection
    }

    private func assertQuerySucceeded(
        _ connection: SPMySQLConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            connection.queryErrored(),
            connection.lastErrorMessage() ?? "Unknown MySQL error",
            file: file,
            line: line
        )
    }

    private func backtickQuoted(_ identifier: String) -> String {
        "`\(identifier.replacingOccurrences(of: "`", with: "``"))`"
    }
}
