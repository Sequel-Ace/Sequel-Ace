//
//  SPCustomQuerySQLClassifierTests.swift
//  Unit Tests
//

import XCTest

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
    }

    func testDatabaseContextSupportsDropCreateUseRebuildSequence() {
        var databaseName: String? = "app_db"

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
}
