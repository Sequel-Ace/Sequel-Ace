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
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "USE new_db; -- selected\n", currentDatabase: "old_db"),
            "new_db"
        )
        XCTAssertEqual(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "/* before */ USE `new``db/*literal*/#name` /* after */", currentDatabase: "old_db"),
            "new`db/*literal*/#name"
        )
        XCTAssertEqual(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "USE hash_db # selected", currentDatabase: "old_db"),
            "hash_db"
        )
        XCTAssertEqual(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "USEFUL db", currentDatabase: "old_db"),
            "old_db"
        )
    }

    func testDatabaseContextClearsOnlyWhenTheCurrentDatabaseWasDropped() {
        XCTAssertNil(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "DROP DATABASE `app_db`", currentDatabase: "app_db")
        )
        XCTAssertNil(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "DROP SCHEMA IF EXISTS app_db; -- rebuild", currentDatabase: "app_db")
        )
        XCTAssertEqual(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "DROP DATABASE reporting", currentDatabase: "app_db"),
            "app_db"
        )
        XCTAssertEqual(
            SASQLDatabaseContext.databaseName(afterSuccessfulQuery: "DROP DATABASE app_db_backup", currentDatabase: "app_db"),
            "app_db"
        )
    }

    func testDatabaseContextSupportsDropCreateUseRebuildSequence() {
        var databaseName: String? = "app_db"

        databaseName = SASQLDatabaseContext.databaseName(
            afterSuccessfulQuery: "DROP DATABASE app_db",
            currentDatabase: databaseName
        )
        XCTAssertNil(databaseName)

        databaseName = SASQLDatabaseContext.databaseName(
            afterSuccessfulQuery: "CREATE DATABASE app_db",
            currentDatabase: databaseName
        )
        XCTAssertNil(databaseName)

        databaseName = SASQLDatabaseContext.databaseName(
            afterSuccessfulQuery: "USE app_db; /* restored */",
            currentDatabase: databaseName
        )
        XCTAssertEqual(databaseName, "app_db")
    }
}
