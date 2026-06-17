import XCTest

final class SAMySQL84ForeignKeyRuleSupportTests: XCTestCase {
    func testForeignKeyRulesOnlyApplyToMySQL84AndNewer() {
        XCTAssertFalse(SAMySQL84ForeignKeyRuleSupport.usesMySQL84ForeignKeyRules(isMariaDB: true, serverVersionIsAtLeast84: true, restrictionQueryErrored: false, restrictionValue: "ON"))
        XCTAssertFalse(SAMySQL84ForeignKeyRuleSupport.usesMySQL84ForeignKeyRules(isMariaDB: false, serverVersionIsAtLeast84: false, restrictionQueryErrored: false, restrictionValue: "ON"))
        XCTAssertTrue(SAMySQL84ForeignKeyRuleSupport.usesMySQL84ForeignKeyRules(isMariaDB: false, serverVersionIsAtLeast84: true, restrictionQueryErrored: true, restrictionValue: nil))
    }

    func testRestrictionValueDisablesRulesForFalseLikeValues() {
        XCTAssertFalse(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: "0"))
        XCTAssertFalse(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: 0))
        XCTAssertFalse(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: " off "))
        XCTAssertFalse(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: "FALSE"))
    }

    func testRestrictionValueDefaultsToEnabled() {
        XCTAssertTrue(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: nil))
        XCTAssertTrue(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: NSNull()))
        XCTAssertTrue(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: "1"))
        XCTAssertTrue(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: "ON"))
        XCTAssertTrue(SAMySQL84ForeignKeyRuleSupport.foreignKeyRulesEnabled(forRestrictionValue: "TRUE"))
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
        let columns = SAMySQL84ForeignKeyRuleSupport.singleColumnUniqueReferenceColumns(indexRows)

        return Set(columns.compactMap { $0 as? String })
    }
}
