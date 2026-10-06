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

    private func supports(mariaDB: Bool, _ major: Int, _ minor: Int, _ release: Int) -> Bool {
        SACheckConstraintSupport.serverSupportsCheckConstraints(isMariaDB: mariaDB, major: major, minor: minor, release: release)
    }

    private func drop(mariaDB: Bool, _ major: Int, _ minor: Int, _ release: Int) -> String {
        SACheckConstraintSupport.dropStatement(table: "t", name: "ck", isMariaDB: mariaDB, major: major, minor: minor, release: release)
    }
}
