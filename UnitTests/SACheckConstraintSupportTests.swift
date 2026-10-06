import XCTest

final class SACheckConstraintSupportTests: XCTestCase {

    // MARK: - Server support

    func testMySQLSupportBeginsAt8016() {
        XCTAssertFalse(supports(mariaDB: false, 5, 7, 44))
        XCTAssertFalse(supports(mariaDB: false, 8, 0, 15))
        XCTAssertTrue(supports(mariaDB: false, 8, 0, 16))
        XCTAssertTrue(supports(mariaDB: false, 8, 4, 0))
        XCTAssertTrue(supports(mariaDB: false, 9, 0, 0))
    }

    func testMariaDBSupportBeginsAt1021() {
        XCTAssertFalse(supports(mariaDB: true, 5, 5, 0))
        XCTAssertFalse(supports(mariaDB: true, 10, 1, 40))
        XCTAssertFalse(supports(mariaDB: true, 10, 2, 0))
        XCTAssertTrue(supports(mariaDB: true, 10, 2, 1))
        XCTAssertTrue(supports(mariaDB: true, 11, 4, 2))
    }

    func testMariaDBVersionNumberingIsNotComparedAgainstMySQLThreshold() {
        // MariaDB 10.x is numerically above MySQL 8.0.16 but 10.1 must still be rejected.
        XCTAssertFalse(supports(mariaDB: true, 10, 1, 48))
    }

    // MARK: - Effective version

    func testMariaDBHandshakePrefixIsIgnored() {
        // The client library reports 5.5.5 for MariaDB 10+, so the string has to be used
        XCTAssertEqual(effective("5.5.5-10.11.19-MariaDB-ubu2204", mariaDB: true, reported: (5, 5, 5)), [10, 11, 19])
        XCTAssertEqual(effective("5.5.5-10.1.48-MariaDB-1~bionic", mariaDB: true, reported: (5, 5, 5)), [10, 1, 48])
    }

    func testMariaDBWithoutHandshakePrefix() {
        XCTAssertEqual(effective("10.11.19-MariaDB", mariaDB: true, reported: (10, 11, 19)), [10, 11, 19])
        XCTAssertEqual(effective("11.4.2-MariaDB-log", mariaDB: true, reported: (5, 5, 5)), [11, 4, 2])
    }

    func testOldMariaDBKeepsItsOwnVersion() {
        // MariaDB 5.5.x is a real version, not the handshake prefix
        XCTAssertEqual(effective("5.5.68-MariaDB", mariaDB: true, reported: (5, 5, 68)), [5, 5, 68])
    }

    func testMySQLNumbersAreReturnedUnchanged() {
        XCTAssertEqual(effective("8.0.18", mariaDB: false, reported: (8, 0, 18)), [8, 0, 18])
        // Even a string that looks like something else: only MariaDB is re-read
        XCTAssertEqual(effective("5.5.5-10.11.19-MariaDB", mariaDB: false, reported: (5, 5, 5)), [5, 5, 5])
    }

    func testUnparseableMariaDBStringFallsBackToReportedNumbers() {
        XCTAssertEqual(effective(nil, mariaDB: true, reported: (10, 6, 1)), [10, 6, 1])
        XCTAssertEqual(effective("MariaDB", mariaDB: true, reported: (10, 6, 1)), [10, 6, 1])
        XCTAssertEqual(effective("10.6-MariaDB", mariaDB: true, reported: (10, 6, 1)), [10, 6, 1])
    }

    func testCorrectedMariaDBVersionPassesTheSupportGate() {
        let version = SACheckConstraintSupport.effectiveVersion(serverVersionString: "5.5.5-10.11.19-MariaDB", isMariaDB: true, major: 5, minor: 5, release: 5)

        XCTAssertFalse(supports(mariaDB: true, 5, 5, 5), "the raw reported version is what hid the section")
        XCTAssertTrue(supports(mariaDB: true, version[0].intValue, version[1].intValue, version[2].intValue))
    }

    // MARK: - Statements

    func testAddStatementNamed() {
        XCTAssertEqual(
            SACheckConstraintSupport.addStatement(table: "user", name: "user.min_username_length", expression: "LENGTH(`username`) >= 6"),
            "ALTER TABLE `user` ADD CONSTRAINT `user.min_username_length` CHECK (LENGTH(`username`) >= 6)"
        )
    }

    func testAddStatementUnnamedOmitsConstraintClause() {
        XCTAssertEqual(
            SACheckConstraintSupport.addStatement(table: "t", name: "  ", expression: " a > 0 "),
            "ALTER TABLE `t` ADD CHECK (a > 0)"
        )
    }

    func testAddStatementNotEnforcedAppendsClause() {
        XCTAssertEqual(
            SACheckConstraintSupport.addStatement(table: "t", name: "ck", expression: "a > 0", enforced: false),
            "ALTER TABLE `t` ADD CONSTRAINT `ck` CHECK (a > 0) NOT ENFORCED"
        )
    }

    func testAddStatementEnforcedHasNoSuffix() {
        XCTAssertEqual(
            SACheckConstraintSupport.addStatement(table: "t", name: "ck", expression: "a > 0", enforced: true),
            "ALTER TABLE `t` ADD CONSTRAINT `ck` CHECK (a > 0)"
        )
    }

    func testNotEnforcedIsMySQLOnlyFrom8016() {
        XCTAssertFalse(SACheckConstraintSupport.serverSupportsNotEnforced(isMariaDB: false, major: 8, minor: 0, release: 15))
        XCTAssertTrue(SACheckConstraintSupport.serverSupportsNotEnforced(isMariaDB: false, major: 8, minor: 0, release: 16))
        XCTAssertTrue(SACheckConstraintSupport.serverSupportsNotEnforced(isMariaDB: false, major: 9, minor: 0, release: 0))
        XCTAssertFalse(SACheckConstraintSupport.serverSupportsNotEnforced(isMariaDB: true, major: 11, minor: 4, release: 2))
    }

    func testAddStatementEscapesBackticksInIdentifiers() {
        XCTAssertEqual(
            SACheckConstraintSupport.addStatement(table: "we`ird", name: "c`k", expression: "a > 0"),
            "ALTER TABLE `we``ird` ADD CONSTRAINT `c``k` CHECK (a > 0)"
        )
    }

    func testDropStatementUsesDropCheckOnEarlyMySQL8() {
        XCTAssertEqual(drop(mariaDB: false, 8, 0, 16), "ALTER TABLE `t` DROP CHECK `ck`")
        XCTAssertEqual(drop(mariaDB: false, 8, 0, 18), "ALTER TABLE `t` DROP CHECK `ck`")
    }

    func testDropStatementUsesDropConstraintFromMySQL8019AndOnMariaDB() {
        XCTAssertEqual(drop(mariaDB: false, 8, 0, 19), "ALTER TABLE `t` DROP CONSTRAINT `ck`")
        XCTAssertEqual(drop(mariaDB: false, 8, 4, 0), "ALTER TABLE `t` DROP CONSTRAINT `ck`")
        XCTAssertEqual(drop(mariaDB: true, 10, 2, 1), "ALTER TABLE `t` DROP CONSTRAINT `ck`")
        // Version 10.x must not be mistaken for an old MySQL.
        XCTAssertEqual(drop(mariaDB: true, 10, 6, 0), "ALTER TABLE `t` DROP CONSTRAINT `ck`")
    }

    func testNameCollisionIsCaseInsensitive() {
        XCTAssertTrue(SACheckConstraintSupport.isName("CK_Age", takenIn: ["fk_a", "ck_age"]))
        XCTAssertFalse(SACheckConstraintSupport.isName("ck_other", takenIn: ["fk_a", "ck_age"]))
        XCTAssertFalse(SACheckConstraintSupport.isName("ck", takenIn: []))
    }

    // MARK: - Parsing: MySQL 8

    func testParsesMySQL8DoubleWrappedExpression() throws {
        let parsed = try parse("CONSTRAINT `user_chk_1` CHECK ((char_length(`username`) >= 6))")

        XCTAssertEqual(parsed.name, "user_chk_1")
        XCTAssertEqual(parsed.expression, "char_length(`username`) >= 6")
        XCTAssertTrue(parsed.enforced)
    }

    func testParsesNotEnforcedMarker() throws {
        let parsed = try parse("CONSTRAINT `c` CHECK ((`a` > 0)) /*!80016 NOT ENFORCED */")

        XCTAssertEqual(parsed.expression, "`a` > 0")
        XCTAssertFalse(parsed.enforced)
    }

    func testKeepsParenthesesThatDoNotEncloseTheWholeExpression() throws {
        let parsed = try parse("CONSTRAINT `c` CHECK (((`a` > 0) and (`b` > 0)))")

        XCTAssertEqual(parsed.expression, "(`a` > 0) and (`b` > 0)")
    }

    func testParsesRegexExpressionLikeTheOneInTheIssue() throws {
        let definition = #"CONSTRAINT `user.email_validation` CHECK ((`email` regexp _utf8mb4\'^[a-z0-9]+@[a-z0-9]+\\.[a-z]{2,63}$\'))"#
        let parsed = try parse(definition)

        XCTAssertEqual(parsed.name, "user.email_validation")
        XCTAssertTrue(parsed.expression.hasPrefix("`email` regexp"))
        XCTAssertTrue(parsed.expression.hasSuffix(#"{2,63}$\'"#))
    }

    func testParenthesesInsideEscapedLiteralDoNotBreakMatching() throws {
        let definition = #"CONSTRAINT `c` CHECK ((`s` regexp _utf8mb4\'^(a|b)\\(x\'))"#
        let parsed = try parse(definition)

        XCTAssertEqual(parsed.expression, #"`s` regexp _utf8mb4\'^(a|b)\\(x\'"#)
    }

    func testParenthesesInsideStringLiteralsDoNotBreakMatching() throws {
        let parsed = try parse("CONSTRAINT `c` CHECK ((`s` <> _utf8mb4')'))")

        XCTAssertEqual(parsed.expression, "`s` <> _utf8mb4')'")
    }

    func testDoubledQuotesInsideStringLiterals() throws {
        let parsed = try parse("CONSTRAINT `c` CHECK ((`s` <> 'it''s (ok'))")

        XCTAssertEqual(parsed.expression, "`s` <> 'it''s (ok'")
    }

    func testCommasInsideInListAreKept() throws {
        let parsed = try parse("CONSTRAINT `c` CHECK ((`status` in (1,2,3)))")

        XCTAssertEqual(parsed.expression, "`status` in (1,2,3)")
    }

    func testEscapedBacktickInName() throws {
        let parsed = try parse("CONSTRAINT `we``ird` CHECK ((`a` > 0))")

        XCTAssertEqual(parsed.name, "we`ird")
    }

    // MARK: - Parsing: MariaDB

    func testParsesMariaDBStyle() throws {
        let parsed = try parse("CONSTRAINT `CONSTRAINT_1` CHECK (`age` >= 0 and `age` <= 150)")

        XCTAssertEqual(parsed.name, "CONSTRAINT_1")
        XCTAssertEqual(parsed.expression, "`age` >= 0 and `age` <= 150")
        XCTAssertTrue(parsed.enforced)
    }

    func testParsesUnnamedCheck() throws {
        let parsed = try parse("CHECK (`a` > 0)")

        XCTAssertEqual(parsed.name, "")
        XCTAssertEqual(parsed.expression, "`a` > 0")
    }

    func testParsesCaseInsensitiveKeywordsAndExtraWhitespace() throws {
        let parsed = try parse("  constraint   `c`   check   ( a > 0 )  ")

        XCTAssertEqual(parsed.name, "c")
        XCTAssertEqual(parsed.expression, "a > 0")
    }

    // MARK: - Parsing: things that are not CHECK constraints

    func testRejectsForeignKeyConstraint() {
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("CONSTRAINT `fk` FOREIGN KEY (`a`) REFERENCES `p` (`id`) ON DELETE CASCADE"))
    }

    func testRejectsIndexesAndColumns() {
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("PRIMARY KEY (`id`)"))
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("UNIQUE KEY `u` (`a`)"))
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("`id` int NOT NULL AUTO_INCREMENT"))
        XCTAssertNil(SACheckConstraintSupport.parseDefinition(""))
    }

    func testRejectsKeywordPrefixes() {
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("CHECKSUM (`a`)"))
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("CONSTRAINTS `x` CHECK (a > 0)"))
    }

    func testRejectsUnbalancedExpression() {
        XCTAssertNil(SACheckConstraintSupport.parseDefinition("CONSTRAINT `c` CHECK ((a > 0)"))
    }

    // MARK: - Helpers

    private struct Parsed {
        let name: String
        let expression: String
        let enforced: Bool
    }

    private func parse(_ definition: String, file: StaticString = #filePath, line: UInt = #line) throws -> Parsed {
        let result = try XCTUnwrap(SACheckConstraintSupport.parseDefinition(definition), file: file, line: line)

        return Parsed(
            name: try XCTUnwrap(result[SACheckConstraintSupport.nameKey] as? String, file: file, line: line),
            expression: try XCTUnwrap(result[SACheckConstraintSupport.expressionKey] as? String, file: file, line: line),
            enforced: try XCTUnwrap(result[SACheckConstraintSupport.enforcedKey] as? NSNumber, file: file, line: line).boolValue
        )
    }

    private func effective(_ string: String?, mariaDB: Bool, reported: (Int, Int, Int)) -> [Int] {
        SACheckConstraintSupport
            .effectiveVersion(serverVersionString: string, isMariaDB: mariaDB, major: reported.0, minor: reported.1, release: reported.2)
            .map(\.intValue)
    }

    private func supports(mariaDB: Bool, _ major: Int, _ minor: Int, _ release: Int) -> Bool {
        SACheckConstraintSupport.serverSupportsCheckConstraints(isMariaDB: mariaDB, major: major, minor: minor, release: release)
    }

    private func drop(mariaDB: Bool, _ major: Int, _ minor: Int, _ release: Int) -> String {
        SACheckConstraintSupport.dropStatement(table: "t", name: "ck", isMariaDB: mariaDB, major: major, minor: minor, release: release)
    }
}
