//
//  SPCustomQuerySQLClassifierTests.swift
//  Unit Tests
//

import XCTest

final class SPCustomQuerySQLClassifierTests: XCTestCase {

    func testExplainableAcceptsOnlySelectAndWith() {
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("SELECT * FROM t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQueryExplainable("(WITH cte AS (SELECT 1) SELECT * FROM cte)"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("EXPLAIN SELECT * FROM t"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("UPDATE t SET c = 1"))
        XCTAssertFalse(SPCustomQuerySQLClassifier.isQueryExplainable("SELECTOR_TABLE"))
    }

    func testPlainExplainPlanInspectionIsSafe() {
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN SELECT * FROM t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("EXPLAIN FORMAT=JSON UPDATE t SET c = 1"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("DESCRIBE t"))
        XCTAssertTrue(SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning("DESC t"))
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
}
