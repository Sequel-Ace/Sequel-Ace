import XCTest

final class SACheckConstraintsModelTests: XCTestCase {

    func testUpdateMapsParsedDictionariesToRows() {
        let model = SACheckConstraintsModel()

        model.update(checks: [
            check("ck_age", "`age` >= 0", enforced: true),
            check("ck_flag", "`flag` in (0,1)", enforced: false)
        ], takenNames: [])

        XCTAssertEqual(model.items.map(\.name), ["ck_age", "ck_flag"])
        XCTAssertEqual(model.items.map(\.expression), ["`age` >= 0", "`flag` in (0,1)"])
        XCTAssertEqual(model.items.map(\.isEnforced), [true, false])
    }

    func testUpdateToleratesMissingKeys() {
        let model = SACheckConstraintsModel()

        model.update(checks: [[:]], takenNames: [])

        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.items[0].name, "")
        XCTAssertEqual(model.items[0].expression, "")
        XCTAssertTrue(model.items[0].isEnforced)
    }

    func testSelectionSurvivesRefreshByName() {
        let model = SACheckConstraintsModel()
        model.update(checks: [check("a", "x > 0"), check("b", "y > 0")], takenNames: [])
        model.selection = [model.items[1].id]

        // "b" moves to the front after "a" is dropped.
        model.update(checks: [check("b", "y > 0")], takenNames: [])

        XCTAssertEqual(model.selectedNames, ["b"])
    }

    func testSelectionIsClearedWhenConstraintDisappears() {
        let model = SACheckConstraintsModel()
        model.update(checks: [check("a", "x > 0")], takenNames: [])
        model.selection = [model.items[0].id]

        model.update(checks: [], takenNames: [])

        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.selectedNames.isEmpty)
    }

    func testCanDeleteNeedsASelectionAndInteraction() {
        let model = SACheckConstraintsModel()
        model.update(checks: [check("a", "x > 0")], takenNames: [])

        XCTAssertFalse(model.canDelete)

        model.selection = [model.items[0].id]
        XCTAssertTrue(model.canDelete)

        model.isEnabled = false
        XCTAssertFalse(model.canDelete)
    }

    func testNameProblemFlagsDuplicatesIncludingForeignKeyNames() {
        let model = SACheckConstraintsModel()
        model.update(checks: [], takenNames: ["fk_parent", "ck_age"])

        XCTAssertNotNil(model.nameProblem(for: "FK_Parent"))
        XCTAssertNotNil(model.nameProblem(for: "  ck_age  "))
        XCTAssertNil(model.nameProblem(for: "ck_other"))
    }

    func testEmptyNameIsAllowed() {
        let model = SACheckConstraintsModel()
        model.update(checks: [], takenNames: [""])

        XCTAssertNil(model.nameProblem(for: ""))
        XCTAssertNil(model.nameProblem(for: "   "))
    }

    func testCanAddRequiresExpressionAndFreeName() {
        let model = SACheckConstraintsModel()
        model.update(checks: [], takenNames: ["ck_age"])

        XCTAssertTrue(model.canAdd(name: "", expression: "a > 0"))
        XCTAssertTrue(model.canAdd(name: "ck_new", expression: "a > 0"))
        XCTAssertFalse(model.canAdd(name: "ck_new", expression: "   "))
        XCTAssertFalse(model.canAdd(name: "ck_age", expression: "a > 0"))
    }

    // MARK: - Shared names with a foreign key

    func testOnMySQLACheckNameUsedByAForeignKeyIsFreeToAdd() {
        let model = SACheckConstraintsModel()
        model.update(checks: [], takenNames: namesToAvoid(foreignKeys: ["fk_parent"], checks: [], isMariaDB: false))

        XCTAssertNil(model.nameProblem(for: "fk_parent"))
        XCTAssertTrue(model.canAdd(name: "fk_parent", expression: "a > 0"))
    }

    func testOnMySQLDeletingACheckThatSharesANameWithAForeignKeyAllowsAddingItAgain() {
        let model = SACheckConstraintsModel()

        // Before: the check and the foreign key are both called ck, so the name is taken by the check
        model.update(checks: [check("ck", "`a` > 0")], takenNames: namesToAvoid(foreignKeys: ["ck"], checks: ["ck"], isMariaDB: false))
        XCTAssertNotNil(model.nameProblem(for: "ck"))

        // After deleting the check, the foreign key remains but must not block the name
        model.update(checks: [], takenNames: namesToAvoid(foreignKeys: ["ck"], checks: [], isMariaDB: false))
        XCTAssertNil(model.nameProblem(for: "ck"))
        XCTAssertTrue(model.canAdd(name: "ck", expression: "a > 0"))
    }

    func testOnMariaDBTheForeignKeyStillBlocksTheCheckName() {
        let model = SACheckConstraintsModel()
        model.update(checks: [], takenNames: namesToAvoid(foreignKeys: ["ck"], checks: [], isMariaDB: true))

        XCTAssertNotNil(model.nameProblem(for: "ck"))
        XCTAssertFalse(model.canAdd(name: "ck", expression: "a > 0"))
    }

    func testNotEnforcedIsNotOfferedUntilTheServerSupportsIt() {
        XCTAssertFalse(SACheckConstraintsModel().supportsNotEnforced)
    }

    // MARK: - Helpers

    private func namesToAvoid(foreignKeys: [String], checks: [String], isMariaDB: Bool) -> [String] {
        SACheckConstraintSupport.namesToAvoidForNewCheck(foreignKeyNames: foreignKeys, checkNames: checks, isMariaDB: isMariaDB)
    }

    private func check(_ name: String, _ expression: String, enforced: Bool = true) -> [String: Any] {
        [
            SACheckConstraintSupport.nameKey: name,
            SACheckConstraintSupport.expressionKey: expression,
            SACheckConstraintSupport.enforcedKey: NSNumber(value: enforced)
        ]
    }
}
