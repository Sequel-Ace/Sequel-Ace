import XCTest

final class SAClaudeAlertKindTests: XCTestCase {
    private func classify(_ title: String, _ message: String = "", _ buttons: [String], fromError: Bool = false) -> SAClaudeAlertClassification {
        SAClaudeAlertKind.classify(SAClaudeAlertFacts(title: title, message: message, buttonTitles: buttons, isFromError: fromError))
    }
    private func c(_ kind: SAClaudeAlertKind, red: Int? = nil) -> SAClaudeAlertClassification { .init(kind: kind, destructiveButtonIndices: red.map { [$0] } ?? []) }
    private func c(_ kind: SAClaudeAlertKind, reds: [Int]) -> SAClaudeAlertClassification { .init(kind: kind, destructiveButtonIndices: reds) }
    private func split(_ title: String, _ message: String) -> SAClaudeAlertMessageParts {
        SAClaudeAlertMessageSplit.split(title: title, message: message)
    }
    private func parts(_ explanation: String, _ server: String?) -> SAClaudeAlertMessageParts {
        .init(explanation: explanation, serverText: server)
    }

    /// Every row of the spec's table (messages from the real call sites).
    func testSpecTable() {
        XCTAssertEqual(classify("Delete database 'x'?", "Are you sure you want to delete the database 'x'? This operation cannot be undone.", ["Delete", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Delete selected row?", "Are you sure you want to delete the selected row from this table? This action cannot be undone.", ["Delete", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Truncate table 'x'", "Are you sure you want to delete ALL records in the table 'x'? This operation cannot be undone.", ["Truncate", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Kill query?", "Are you sure you want to kill the current query executing on connection ID 42?\n\nPlease be aware that continuing to kill this query may result in data corruption. Please proceed with caution.", ["Kill query", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Error adding new table", "An error occurred while trying to add the new table 'x'.\n\nMySQL said: Unknown database 'y'", ["OK"]), c(.error))
        XCTAssertEqual(classify("Insufficient connection details", "Insufficient details provided to establish a connection. Please provide at least a host.", ["OK"]), c(.error))
        XCTAssertEqual(classify("Empty query", "Cannot save an empty query.", ["OK"]), c(.error))
        XCTAssertEqual(classify("Execute SQL?", "Do you really want to proceed with this query?\n\n DROP TABLE `x`\n", ["Proceed", "Cancel"]), c(.question))
        XCTAssertEqual(classify("MySQL Error", "You have an error in your SQL syntax; check the manual", ["Run All", "Continue", "Stop"]), c(.error))
        XCTAssertEqual(classify("An error occurred while importing SQL", "[ERROR in query 3] Table 'x' already exists\n", ["Continue", "Ignore All Errors", "Stop"]), c(.error))
        XCTAssertEqual(classify("Change table type", "Are you sure you want to change this table's type to MyISAM?\n\nPlease be aware that changing a table's type has the potential to cause the loss of some or all of its data. This action cannot be undone.", ["Change", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Delete index 'x'?", "Are you sure you want to delete the index 'x'? This action cannot be undone.", ["Delete", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Flushed Privileges", "Successfully flushed privileges.", ["OK"]), c(.info))
        XCTAssertEqual(classify("Default Bundles Update", "The following default Bundles were updated:\nx\nYour modifications were stored as “(user)”.", ["OK"]), c(.info))
        XCTAssertEqual(classify("Only Partially Supported", "Duplicating the database 'x' is only partially supported as it contains objects other than tables (i.e. views, procedures, functions, etc.), which will not be copied.\n\nWould you like to continue?", ["OK"]), c(.warning))
        XCTAssertEqual(classify("A new version is available", "Version 5.1.0 is available. You are currently running 5.0.9", ["View", "Download", "Cancel"]), c(.question))
    }

    func testRealCallSiteVariants() {
        XCTAssertEqual(classify("Kill query?", "Are you sure you want to kill the current query executing on connection ID 42?\n\nPlease be aware that continuing to kill this query may result in data corruption. Please proceed with caution.", ["Kill", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Delete rows?", "Are you sure you want to delete the selected rows? This action cannot be undone.", ["Delete Selected Rows", "Delete ALL ROWS IN TABLE", "Cancel"]), c(.destructive, reds: [0, 1]))
        XCTAssertEqual(classify("Only Partially Supported", "Duplicating the database 'x' is only partially supported as it contains objects other than tables (i.e. views, procedures, functions, etc.), which will not be copied.\n\nWould you like to continue?", ["Continue", "Cancel"]), c(.question))
        XCTAssertEqual(classify("Error", "Couldn't delete 'x'.\n\nSelecting the 'Force delete' option may prevent this issue, but may leave the database in an inconsistent state.\n\nMySQL said: Cannot delete or update a parent row", ["Continue", "Stop"]), c(.error))
        XCTAssertEqual(classify("Connection lost", "The connection to the server was lost.", ["Reconnect", "Close"]), c(.question))
    }

    /// Tuning against the real call sites (Task 3 classification report): each case cites the site that motivated it.
    func testCallSiteTuning() {
        // SPDataImport.m:318 — importing may overwrite data: a destructive choice, the confirming button turns red.
        XCTAssertEqual(classify("The current database already has existing tables, importing may overwrite data. Are you sure you want to continue?", "The chosen import file can potentially overwrite existing data. You should use caution when proceeding with the import.", ["Yes, continue anyway", "Cancel"]), c(.destructive, red: 0))
        // SPExportController.m:2044 — replacing a file overwrites its contents.
        XCTAssertEqual(classify("“x” already exists. Do you want to replace it?", "A file with the same name already exists in the target folder. Replacing it will overwrite its current contents.", ["Replace", "Cancel", "Skip existing"]), c(.destructive, red: 0))
        // SPUserManager.m:983 — changes that will be lost.
        XCTAssertEqual(classify("Unsaved changes", "Changes have been made, which will be lost if this window is closed. Are you sure you want to continue?", ["Continue", "Cancel"]), c(.destructive, red: 0))
        // SPDataImport.m:603 — characters "will be unrecoverably lost!".
        XCTAssertEqual(classify("Incompatible encoding in SQL file", "You can continue the import, but any non-BMP characters in the SQL file will be unrecoverably lost!", ["Import Anyway", "Cancel"]), c(.destructive, red: 0))
        // SPEditorPreferencePane.m:786 — proceeding without saving discards the theme.
        XCTAssertEqual(classify("Unsaved Theme", "The current color theme is unsaved. Do you want to proceed without saving it?", ["Proceed", "Cancel"]), c(.destructive, red: 0))
        // ... but a lost connection is not data loss (spec table: Reconnect / Close stays a Question).
        XCTAssertEqual(classify("Connection lost", "The connection to the server was lost.", ["Reconnect", "Close"]), c(.question))
        // SPTableContent.m:1522 — "information" must not make a failure read as Info.
        XCTAssertEqual(classify("Table contents not loaded", "The column list for 'x' did not match the data the server returned, and reloading the table did not settle it. This usually means the connection dropped while the table information was read.\n\nCheck the connection, then reload the table.", ["OK"]), c(.warning))
        // GitHubReleaseManager.swift:299 — "up to date" in other words is Info.
        XCTAssertEqual(classify("No Newer Release Available", "You are currently running the latest release.", ["OK"]), c(.info))
        // SPDatabaseDocument.m:1990 — the plural of the spec's "checksum" (results table accessory, no message).
        XCTAssertEqual(classify("Checksums of selected items", "", ["OK"]), c(.info))
        // SABundleHTMLOutputWindowController.swift:195 — a JavaScript exception is a failure.
        XCTAssertEqual(classify("JavaScript Exception", "Exception:\nline = 3\nmessage = x\nsource = y", ["OK"]), c(.error))
    }

    /// The data-loss fallback reddens the button that gives the changes up, never the "Save" that keeps them.
    func testDataLossRedIsDontSaveNeverSave() {
        let lost = "Changes have been made, which will be lost if this window is closed."
        XCTAssertEqual(classify("Unsaved changes", lost, ["Save", "Don't Save", "Cancel"]), c(.destructive, red: 1))
        XCTAssertEqual(classify("Unsaved changes", lost, ["Save", "Don\u{2019}t Save", "Cancel"]), c(.destructive, red: 1))
        XCTAssertEqual(classify("Unsaved changes", lost, ["Save", "Discard", "Cancel"]), c(.destructive, red: 1))
        XCTAssertEqual(classify("Unsaved changes", lost, ["Don't Save", "Save", "Cancel"]), c(.destructive, red: 0))
        XCTAssertEqual(classify("Unsaved changes", lost, ["Save", "Cancel"]), c(.destructive, red: nil), "no button but Save: nothing turns red")
        XCTAssertEqual(classify("Unsaved changes", lost, ["Continue", "Cancel"]), c(.destructive, red: 0))
    }

    func testNegatedCompletionIsNotInfo() {
        for message in ["The export was not saved.", "The rows weren't imported.", "The file isn't updated.", "Never copied.", "Results of the check are unavailable.", "Results of the check are missing."] {
            XCTAssertEqual(classify("Notice", message, ["OK"]), c(.warning), message)
        }
        XCTAssertEqual(classify("Notice", "The export was saved.", ["OK"]), c(.info))
    }

    func testCheckTableSuccessIsInfoFailureIsError() {
        XCTAssertEqual(classify("Check table 'x'", "Check table successfully passed.\n\nMySQL said: OK", ["OK"]), c(.info))
        XCTAssertEqual(classify("Check table 'x'", "Check table failed.\n\nMySQL said: Table is marked as crashed", ["OK"]), c(.error))
        XCTAssertEqual(classify("Error while checking selected items", "MySQL said:", ["OK"]), c(.error))
    }

    func testDestructiveButtonWords() {
        let words = ["Delete", "Remove", "Drop", "Truncate", "Kill", "Clear", "Empty", "Shutdown", "Shut Down", "Discard", "Force Delete", "Reset", "Overwrite", "delete", "DELETE"]
        for word in words {
            XCTAssertEqual(classify("Sure?", "", [word + " it", "Cancel"]), c(.destructive, red: 0), word)
        }
    }

    /// Walkthrough (Kunal): every delete-type button is red, never Cancel.
    func testEveryDeleteTypeButtonIsRed() {
        XCTAssertEqual(classify("Delete selected row?", "Are you sure you want to delete the selected row from this table? This action cannot be undone.", ["Delete Selected Row", "Delete ALL ROWS IN TABLE", "Cancel"]), c(.destructive, reds: [0, 1]))
        XCTAssertEqual(classify("Delete it?", "", ["Cancel", "Delete", "Remove all"]), c(.destructive, reds: [1, 2]))
        XCTAssertEqual(classify("Sure?", "", ["Keep", "Discard", "Reset", "Cancel"]), c(.destructive, reds: [1, 2]))
        // Only the delete-type ones: a neutral sibling stays as it is.
        XCTAssertEqual(classify("Delete rows?", "", ["Delete", "Skip", "Cancel"]), c(.destructive, reds: [0]))
    }

    /// Walkthrough 2 (Kunal): of the destructive buttons, the default one (Return, else the first: the one drawn primary)
    /// stays filled red; every other one is a red dashed outline.
    func testOnlyTheDefaultDestructiveButtonIsFilled() {
        let deleteRow = classify("Delete selected row?", "Are you sure you want to delete the selected row from this table? This action cannot be undone.",
                                 ["Delete Selected Row", "Delete ALL ROWS IN TABLE", "Cancel"])
        // NSAlert gives its first button Return and a "Cancel" button Escape.
        XCTAssertEqual(deleteRow.destructiveLooks(keyEquivalents: ["\r", "", "\u{1b}"]), [0: .filled, 1: .outlined])
        // One destructive button that is the default: filled, as before.
        XCTAssertEqual(c(.destructive, red: 0).destructiveLooks(keyEquivalents: ["\r", "\u{1b}"]), [0: .filled])
        // No Return button: the first button is the default.
        XCTAssertEqual(c(.destructive, reds: [0, 1]).destructiveLooks(keyEquivalents: ["", "", ""]), [0: .filled, 1: .outlined])
        // Return on another button: every destructive button is an outline.
        XCTAssertEqual(c(.destructive, reds: [1, 2]).destructiveLooks(keyEquivalents: ["\r", "", ""]), [1: .outlined, 2: .outlined])
        XCTAssertEqual(c(.destructive, reds: [0]).destructiveLooks(keyEquivalents: ["r", "\r"]), [0: .outlined])
        // "Don't Save" beside the default "Save".
        XCTAssertEqual(c(.destructive, red: 1).destructiveLooks(keyEquivalents: ["\r", "d", "\u{1b}"]), [1: .outlined])
        // Nothing red: nothing to draw.
        XCTAssertEqual(c(.question).destructiveLooks(keyEquivalents: ["\r", "\u{1b}"]), [:])
        // An index past the buttons is ignored.
        XCTAssertEqual(c(.destructive, reds: [0, 5]).destructiveLooks(keyEquivalents: ["\r"]), [0: .filled])
    }

    func testDefaultButtonIndex() {
        XCTAssertEqual(SAClaudeAlertClassification.defaultButtonIndex(keyEquivalents: ["\r", "", "\u{1b}"]), 0)
        XCTAssertEqual(SAClaudeAlertClassification.defaultButtonIndex(keyEquivalents: ["r", "\r"]), 1)
        XCTAssertEqual(SAClaudeAlertClassification.defaultButtonIndex(keyEquivalents: ["", ""]), 0)
        XCTAssertNil(SAClaudeAlertClassification.defaultButtonIndex(keyEquivalents: []))
    }

    func testDestructiveButtonNeedsWordBoundary() {
        XCTAssertEqual(classify("Proceed?", "", ["Clearance", "Cancel"]), c(.question))
    }

    func testCancelIsNeverDestructive() {
        XCTAssertEqual(classify("Delete it?", "", ["Cancel", "Delete"]), c(.destructive, red: 1))
        XCTAssertEqual(classify("Change table type", "This action cannot be undone.", ["Cancel", "Change"]), c(.destructive, red: 1))
        XCTAssertEqual(classify("x", "", ["Cancel…", "Delete"]), c(.destructive, red: 1))
        XCTAssertEqual(classify("Delete x?", "", ["Cancel"]), c(.warning))
    }

    func testTitleQuestionVerbs() {
        for title in ["Drop table x?", "Remove favorite?", "Truncate tables?", "Kill connection?", "Delete rows?"] {
            XCTAssertEqual(classify(title, "", ["Yes", "No"]), c(.destructive, red: 0), title)
        }
        XCTAssertEqual(classify("Delete rows", "", ["Yes", "No"]), c(.question))
    }

    func testDataLossText() {
        for message in ["This can’t be undone.", "Rows are removed permanently.", "You will lose all unsaved data in this tab.", "The loss of some data is possible."] {
            XCTAssertEqual(classify("Sure?", message, ["Go", "Cancel"]), c(.destructive, red: 0), message)
        }
    }

    func testDestructiveTextNeedsAChoice() {
        XCTAssertEqual(classify("Notice", "This cannot be undone.", ["OK"]), c(.warning))
    }

    func testCannotBeUndoneIsNotAFailure() {
        XCTAssertEqual(classify("Notice", "This can't be undone.", ["Close"]), c(.warning))
        XCTAssertEqual(classify("x", "You cannot do that.", ["OK"]), c(.error))
    }

    func testStrongFailureAnyButtons() {
        for message in ["MySQL said: x", "An error occurred", "Errors were found", "The export failed", "Couldn't open the file", "Couldn’t open", "Could not connect", "Unable to read"] {
            XCTAssertEqual(classify("x", message, ["Retry", "Skip", "Stop"]), c(.error), message)
        }
        XCTAssertEqual(classify("x", "", ["A", "B"], fromError: true), c(.error))
    }

    /// Walkthrough (Kunal): a title that states a failure is a strong failure signal, even over a "Reset…" button.
    func testFailureTitleIsAStrongFailure() {
        // SPConnectionController.m:_validateSSHConfigFile — the real buttons.
        XCTAssertEqual(classify("Cannot Access SSH Config File", "Sequel Ace does not have permission to read the configured SSH config file at '/x'.\n\nThis might be due to Sandbox restrictions. You can configure a different SSH Config File in the Network tab of Preferences or correct access to the exiting file in the Files tab of Preferences, or you can reset the path to the Sequel Ace default.",
                           ["Go to Network Settings", "Reset to Default & Continue", "Cancel"]), c(.error))
        for title in ["Cannot open file", "can't open file", "Can\u{2019}t open file", "Can not open file", "Unable to open file", "Couldn't open file", "Couldn\u{2019}t open file", "Could not open file", "Failed to open file", "FAILED to open"] {
            XCTAssertEqual(classify(title, "", ["Reset", "Cancel"]), c(.error), title)
        }
        // "cannot be undone" is data-loss wording, not failure.
        XCTAssertEqual(classify("Cannot be undone", "", ["OK"]), c(.warning))
        XCTAssertEqual(classify("Delete it?", "Cannot be undone.", ["Delete", "Cancel"]), c(.destructive, red: 0))
        // A title that merely contains the word later on is not a failure statement.
        XCTAssertEqual(classify("Reset: cannot go back?", "", ["Reset", "Cancel"]), c(.destructive, red: 0))
    }

    /// Preflight ruling (F15): a strong failure beats a destructive-sounding button title.
    func testStrongFailureBeatsDestructiveButton() {
        XCTAssertEqual(classify("Unable to write row", "The row could not be saved.\n\nMySQL said: Duplicate entry '1' for key 'PRIMARY'", ["Edit row", "Discard changes"]), c(.error))
        // ... but a destructive question or data-loss wording still wins.
        XCTAssertEqual(classify("Delete rows?", "An error may follow. This cannot be undone.", ["Delete", "Cancel"]), c(.destructive, red: 0))
    }

    func testFailureWordsNeedWordBoundaries() {
        XCTAssertEqual(classify("Mirror settings", "Terror-free.", ["OK"]), c(.warning))
    }

    func testWeakFailureOnlyWithSingleAcknowledgeButton() {
        for button in ["OK", "Close", "Done", "Dismiss"] {
            for message in ["Invalid filter", "Table not found", "Access denied", "A name must be given", "The field is empty", "Cannot connect", "Insufficient privileges"] {
                XCTAssertEqual(classify("x", message, [button]).kind, .error, "\(button): \(message)")
            }
        }
        XCTAssertEqual(classify("Invalid filter", "", ["Retry", "Cancel"]), c(.question))
        XCTAssertEqual(classify("Invalid filter", "", ["Edit"]), c(.warning))
    }

    func testInfoWords() {
        let sentences = [
            "The operation was a success.", "The operation was Successful.", "The export finished.", "The import completed.",
            "All done.", "The privileges were flushed.", "The query was saved.", "The rows were exported.", "The rows were imported.",
            "The bundles were updated.", "The server is up to date.", "The text was copied.", "The checksum is 42.",
            "Results of the check", "Result of the check", "Some information for you."
        ]
        for sentence in sentences {
            XCTAssertEqual(classify("Notice", sentence, ["OK"]), c(.info), sentence)
        }
    }

    func testInfoNeedsSingleAcknowledgeButton() {
        XCTAssertEqual(classify("Export finished", "", ["Show", "OK"]), c(.question))
    }

    func testWarningWordsVetoInfo() {
        for title in ["Export finished with a warning", "Saved, but some rows may be missing", "Updated; might need a restart", "Import completed partially", "Copied (deprecated format)", "Saved with limited precision", "Exported; not supported by 5.5"] {
            XCTAssertEqual(classify(title, "", ["OK"]), c(.warning), title)
        }
    }

    func testFallbackIsWarning() {
        XCTAssertEqual(classify("Hello", "Something happened.", ["OK"]), c(.warning))
        XCTAssertEqual(classify("", "", ["OK"]), c(.warning))
    }

    func testNoButtonsMeansImplicitOK() {
        XCTAssertEqual(classify("Flushed Privileges", "Successfully flushed privileges.", []), c(.info))
        XCTAssertEqual(classify("Empty query", "Cannot save an empty query.", []), c(.error))
    }

    func testQuotedNamesDoNotDecideTheKind() {
        XCTAssertEqual(classify("Table 'saved queries' has no primary key", "", ["OK"]), c(.warning))
        XCTAssertEqual(classify("x", "The table “exported rows” has no key.", ["OK"]), c(.warning))
        XCTAssertEqual(classify("x", "Column `error` was renamed.", ["OK"]), c(.warning))
        XCTAssertEqual(classify("Couldn't delete 'x'.", "", ["OK"]), c(.error))
        // Preflight ruling (F6): curly single quotes are detected before they are normalised.
        XCTAssertEqual(classify("x", "The table ‘saved queries’ has no key.", ["OK"]), c(.warning))
    }

    func testOtherLanguagesFallBackSafely() {
        XCTAssertEqual(classify("Base de données supprimée", "Opération réussie.", ["OK"]), c(.warning))
        XCTAssertEqual(classify("Supprimer la base ?", "", ["Supprimer", "Annuler"]), c(.question))
    }

    // MARK: Split

    func testSplitAtMarker() {
        XCTAssertEqual(split("Error adding new table", "An error occurred while trying to add the new table 'x'.\n\nMySQL said: Unknown database 'y'"),
                       parts("An error occurred while trying to add the new table 'x'.", "Unknown database 'y'"))
    }

    func testSplitMarkerOnItsOwnLineOrUnspaced() {
        XCTAssertEqual(split("x", "Couldn't rename 'a'.\n\nMySQL said:\nTable 'b' already exists\n"), parts("Couldn't rename 'a'.", "Table 'b' already exists"))
        XCTAssertEqual(split("x", "An error occurred while trying to check the table.\n\nMySQL said:Lost connection"),
                       parts("An error occurred while trying to check the table.", "Lost connection"))
    }

    func testSplitKeepsEverythingAfterTheMarker() {
        XCTAssertEqual(split("x", "x.\n\nMySQL said: a\n\nMySQL said: b"), parts("x.", "a\n\nMySQL said: b"))
    }

    func testWholeMessageForMySQLErrorTitle() {
        XCTAssertEqual(split("MySQL Error", "You have an error in your SQL syntax\n"), parts("", "You have an error in your SQL syntax"))
        XCTAssertEqual(split("mysql error", "You have an error in your SQL syntax\n"), parts("", "You have an error in your SQL syntax"))
    }

    func testWholeMessageForErrorInQuery() {
        XCTAssertEqual(split("An error occurred while importing SQL", "[ERROR in query 3] Table 'x' already exists\n"),
                       parts("", "[ERROR in query 3] Table 'x' already exists"))
    }

    func testNoBlockWithoutServerText() {
        XCTAssertEqual(split("Flushed Privileges", "Successfully flushed privileges."), parts("Successfully flushed privileges.", nil))
        XCTAssertEqual(split("Error while checking selected items", "MySQL said:"), parts("MySQL said:", nil))
        XCTAssertEqual(split("MySQL Error", ""), parts("", nil))
        XCTAssertEqual(split("x", "MySQL a dit : y"), parts("MySQL a dit : y", nil))
    }
    // MARK: - Eligibility (SwiftUI and other alerts keep today's skin)

    private func facts(alertClass: String = "NSAlert", targets: [String?] = ["NSAlert", "NSAlert"], presenter: String? = nil) -> SAClaudeAlertEligibility.Facts {
        .init(alertClassName: alertClass, buttonTargetClassNames: targets, presentingContentClassName: presenter)
    }

    func testPlainAlertIsEligible() {
        XCTAssertTrue(SAClaudeAlertEligibility.isEligible(facts()))
        XCTAssertTrue(SAClaudeAlertEligibility.isEligible(facts(presenter: "NSView")))
        XCTAssertTrue(SAClaudeAlertEligibility.isEligible(facts(targets: [])))
    }

    func testSubclassIsNotEligible() {
        XCTAssertFalse(SAClaudeAlertEligibility.isEligible(facts(alertClass: "SwiftUI.PlatformAlert")))
        XCTAssertFalse(SAClaudeAlertEligibility.isEligible(facts(alertClass: "Sequel_Ace.SomeAlert")))
    }

    func testForeignButtonTargetIsNotEligible() {
        XCTAssertFalse(SAClaudeAlertEligibility.isEligible(facts(targets: ["NSAlert", "SwiftUI.AlertActionTarget"])))
        XCTAssertFalse(SAClaudeAlertEligibility.isEligible(facts(targets: [nil])))
    }

    func testHostingViewPresenterIsNotEligible() {
        XCTAssertFalse(SAClaudeAlertEligibility.isEligible(facts(presenter: "NSHostingView<SAConnectionFormView>")))
        XCTAssertFalse(SAClaudeAlertEligibility.isEligible(facts(presenter: "_NSHostingView<Foo>")))
    }

    func testHostingViewDetectionByTypeName() {
        XCTAssertTrue(SAClaudeAlertEligibility.isHostingViewClassName("NSHostingView<ProbeSwiftUIView>"))
        XCTAssertTrue(SAClaudeAlertEligibility.isHostingViewClassName("_NSHostingView<X>"))
        XCTAssertFalse(SAClaudeAlertEligibility.isHostingViewClassName("NSView"))
        XCTAssertFalse(SAClaudeAlertEligibility.isHostingViewClassName("NSKVONotifying_NSView"))
    }
}
