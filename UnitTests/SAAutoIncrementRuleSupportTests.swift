import XCTest

final class SAAutoIncrementRuleSupportTests: XCTestCase {
    func testRecognizesAutoIncrementExtraValues() {
        XCTAssertTrue(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue("AUTO_INCREMENT"))
        XCTAssertTrue(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue(" auto_increment\n"))
        XCTAssertTrue(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue("serial default value"))
    }

    func testRejectsNonAutoIncrementExtraValues() {
        XCTAssertFalse(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue("DEFAULT_GENERATED"))
        XCTAssertFalse(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue("on update CURRENT_TIMESTAMP"))
        XCTAssertFalse(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue(""))
        XCTAssertFalse(SAAutoIncrementRuleSupport.isAutoIncrementExtraValue(NSNull()))
    }

    func testAllowsIntegerFieldTypes() {
        XCTAssertTrue(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("TINYINT"))
        XCTAssertTrue(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("smallint"))
        XCTAssertTrue(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("MEDIUMINT(9)"))
        XCTAssertTrue(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement(" INT(11) UNSIGNED "))
        XCTAssertTrue(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("integer"))
        XCTAssertTrue(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("BIGINT(20)\nUNSIGNED"))
    }

    func testRejectsNonIntegerFieldTypes() {
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement(nil))
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement(""))
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("DECIMAL(10,2)"))
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("DOUBLE"))
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("FLOAT"))
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("VARCHAR(255)"))
        XCTAssertFalse(SAAutoIncrementRuleSupport.fieldTypeAllowsAutoIncrement("TIMESTAMP"))
    }
}
