//
//  SPCustomQuery+Script.swift
//  Sequel Ace
//
//  "Run All as Script": runs the editor's statements (or the selection) and
//  prints the output of every statement as mysql -vv batch-mode text in a
//  console that replaces the result grid. See
//  docs/superpowers/specs/2026-10-08-run-as-script-design.md.
//

import AppKit
import SwiftUI

private var scriptConsoleAttachmentKey: UInt8 = 0

/// The console's model and hosting view, kept on SPCustomQuery as an
/// associated object so the legacy class needs no new ivars.
private final class SAScriptConsoleAttachment {
    let model = SAScriptConsoleModel()
    let hostingView: NSHostingView<SAScriptConsoleView>

    init() {
        hostingView = NSHostingView(rootView: SAScriptConsoleView(model: model, defaultSaveFileName: "script-output.txt"))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.isHidden = true
    }
}

extension SPCustomQuery {

    // MARK: - IBAction

    @IBAction
    @objc(runAllAsScriptAction:)
    public func runAllAsScriptAction(_ sender: Any?) {
        guard let document = tableDocumentInstance, !document.isWorking() else { return }
        // Fixes bug in key equivalents (mirrors -runAllQueries: guard).
        if NSApp.currentEvent?.type == .keyUp { return }
        guard let editor = textView else {
            NSSound.beep()
            return
        }

        let selectedRange = editor.selectedRange()
        let sql = selectedRange.length > 0
            ? ((editor.string as NSString).safeSubstring(with: selectedRange) ?? "")
            : editor.string
        let statements = SAScriptStatementSplitter.statements(in: sql)
        guard !statements.isEmpty else {
            NSSound.beep()
            return
        }

        let queries = statements.map(\.text)
        guard UserDefaults.standard.bool(forKey: SPQueryWarningEnabled), queriesContainDestructiveSQL(queries) else {
            startScriptRun(statements)
            return
        }

        // Same confirmation as -performQueries:withCallback:.
        var listing = queries.joined(separator: "\n") + "\n"
        if listing.count > Int(SPMaxQueryLengthForWarning) {
            listing = (listing as NSString).summarize(toLength: UInt(SPMaxQueryLengthForWarning), withEllipsis: true)
        }
        let format = queries.count > 1
            ? NSLocalizedString("Do you really want to proceed with these queries?\n\n %@", comment: "message of panel asking for confirmation for exec query")
            : NSLocalizedString("Do you really want to proceed with this query?\n\n %@", comment: "message of panel asking for confirmation for exec query")
        NSAlert.createDefaultAlert(title: NSLocalizedString("Execute SQL?", comment: "Execute SQL?"),
                                   message: String(format: format, listing),
                                   primaryButtonTitle: NSLocalizedString("Proceed", comment: "Proceed"),
                                   primaryButtonHandler: { [weak self] in self?.startScriptRun(statements) })
    }

    // MARK: - Console visibility

    /// Show the grid again. Called by -performQueriesWithNoWarning:withCallback:.
    @objc func hideScriptConsole() {
        // -performQueriesWithNoWarning: can be called off the main thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.hideScriptConsole() }
            return
        }
        guard let attachment = existingScriptConsoleAttachment, !attachment.hostingView.isHidden else { return }
        // Check before hiding: AppKit moves focus away from a view being hidden.
        let window = attachment.hostingView.window
        let consoleHadFocus = (window?.firstResponder as? NSView)?.isDescendant(of: attachment.hostingView) ?? false
        attachment.hostingView.isHidden = true
        customQueryScrollView?.isHidden = false
        if consoleHadFocus, let grid = customQueryScrollView?.documentView {
            window?.makeFirstResponder(grid)
        }
    }

    private func showScriptConsole() -> SAScriptConsoleAttachment? {
        let attachment = scriptConsoleAttachment()
        guard attachment.hostingView.superview != nil else { return nil }
        let databaseName = tableDocumentInstance?.database() ?? ""
        let fileName = databaseName.isEmpty ? "script-output.txt" : "\(databaseName)-script-output.txt"
        attachment.hostingView.rootView = SAScriptConsoleView(model: attachment.model, defaultSaveFileName: fileName)
        // Check before hiding: AppKit moves focus away from a view being hidden.
        let window = attachment.hostingView.window
        let gridHadFocus = customQueryScrollView.map { grid in
            (window?.firstResponder as? NSView)?.isDescendant(of: grid) ?? false
        } ?? false
        attachment.hostingView.isHidden = false
        customQueryScrollView?.isHidden = true
        if gridHadFocus {
            // The text view only exists once SwiftUI has laid out the hosting view.
            DispatchQueue.main.async { [weak hostingView = attachment.hostingView] in
                guard let hostingView, !hostingView.isHidden,
                      let textView = Self.firstTextView(in: hostingView) else { return }
                hostingView.window?.makeFirstResponder(textView)
            }
        }
        return attachment
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        for subview in view.subviews {
            if let textView = subview as? NSTextView { return textView }
            if let textView = firstTextView(in: subview) { return textView }
        }
        return nil
    }

    private var existingScriptConsoleAttachment: SAScriptConsoleAttachment? {
        objc_getAssociatedObject(self, &scriptConsoleAttachmentKey) as? SAScriptConsoleAttachment
    }

    private func scriptConsoleAttachment() -> SAScriptConsoleAttachment {
        if let existing = existingScriptConsoleAttachment { return existing }
        let attachment = SAScriptConsoleAttachment()
        // Overlay the grid's scroll view inside its container (a plain pane
        // view, not the split view), pinned to the grid's edges so the record
        // view beside it is unaffected.
        if let grid = customQueryScrollView, let container = grid.superview {
            container.addSubview(attachment.hostingView, positioned: .above, relativeTo: grid)
            NSLayoutConstraint.activate([
                attachment.hostingView.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
                attachment.hostingView.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
                attachment.hostingView.topAnchor.constraint(equalTo: grid.topAnchor),
                attachment.hostingView.bottomAnchor.constraint(equalTo: grid.bottomAnchor),
            ])
        }
        objc_setAssociatedObject(self, &scriptConsoleAttachmentKey, attachment, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return attachment
    }

    // MARK: - Run

    private func startScriptRun(_ statements: [SAScriptStatement]) {
        guard let document = tableDocumentInstance, !document.isWorking(),
              let connection = mySQLConnection,
              let attachment = showScriptConsole() else {
            NSSound.beep()
            return
        }

        // Ensure there is no pending edit (#2113), as -performQueriesWithNoWarning: does.
        document.parentWindowControllerWindow()?.endEditing(for: nil)

        attachment.model.clear()
        let continueOnError = UserDefaults.standard.bool(forKey: SAScriptConsoleModel.continueOnErrorDefaultsKey)
        let database = document.database()

        let firstTask = statements.count > 1
            ? String(format: NSLocalizedString("Running query %ld of %lu...", comment: "Running multiple queries string"), 1, statements.count)
            : NSLocalizedString("Running query...", comment: "Running single query string")
        document.startTask(withDescription: firstTask)
        errorTextTitle?.stringValue = NSLocalizedString("Query Status", comment: "Query Status")
        (errorText as? NSTextView)?.textColor = .controlTextColor
        (errorText as? NSText)?.string = firstTask
        (affectedRowsText as? NSTextField)?.stringValue = ""
        // The Stop button calls the token first, then cancels the in-flight query,
        // so the runner also stops while printing buffered rows or between statements.
        let cancellation = SAScriptCancellationToken()
        document.enableTaskCancellation(withTitle: statements.count > 1
                                            ? NSLocalizedString("Stop queries", comment: "Stop queries string")
                                            : NSLocalizedString("Stop query", comment: "Stop query string"),
                                        callbackObject: cancellation,
                                        callbackFunction: #selector(SAScriptCancellationToken.cancel))
        document.setQueryMode(Int(SPQueryMode.customQueryQueryMode.rawValue))
        NotificationCenter.default.post(name: NSNotification.Name("SMySQLQueryWillBePerformed"), object: document)

        let model = attachment.model
        let runner = SAScriptRunner(
            connection: connection,
            cancellation: cancellation,
            output: { model.append($0) },
            progress: { [weak document] index, total in
                guard index > 0 else { return }
                let text = String(format: NSLocalizedString("Running query %ld of %lu...", comment: "Running multiple queries string"), index + 1, total)
                DispatchQueue.main.async { document?.setTaskDescription(text) }
            })

        let thread = Thread { [weak self] in
            let summary = runner.run(statements: statements, database: database, continueOnError: continueOnError)
            DispatchQueue.main.async {
                self?.finishScriptRun(summary, model: model)
            }
        }
        thread.name = "SPCustomQuery script run task"
        thread.start()
    }

    private func finishScriptRun(_ summary: SAScriptRunSummary, model: SAScriptConsoleModel) {
        model.flush()
        guard let document = tableDocumentInstance else { return }

        if summary.tableListNeedsReload || summary.databaseChanged {
            document.setDatabases()
            if summary.databaseChanged {
                document.setCurrentDatabaseFromQueryContext(summary.finalDatabase)
            }
            tablesListInstance?.updateTables(self)
        }

        if !summary.executedStatements.isEmpty {
            addHistoryEntry(summary.executedStatements.joined(separator: ";\n"))
        }

        let hadErrors = summary.errorCount > 0
        errorTextTitle?.stringValue = hadErrors
            ? NSLocalizedString("Last Error Message", comment: "Last Error Message")
            : NSLocalizedString("Query Status", comment: "Query Status")
        (errorText as? NSTextView)?.textColor = (hadErrors || summary.wasCancelled) ? .systemRed : .controlTextColor
        (errorText as? NSText)?.string = summary.wasCancelled
            ? NSLocalizedString("Query cancelled.", comment: "Query cancelled error")
            : (hadErrors ? summary.errorLines.joined(separator: "\n")
                         : NSLocalizedString("There were no errors.", comment: "text shown when query was successfull"))
        (affectedRowsText as? NSTextField)?.stringValue = statusLine(for: summary)

        document.setQueryMode(Int(SPQueryMode.interfaceQueryMode.rawValue))
        NotificationCenter.default.post(name: NSNotification.Name("SMySQLQueryHasBeenPerformed"), object: document)
        SANotificationCenter.shared.postNotification(title: "Query Finished", body: (errorText as? NSText)?.string)
        document.endTask()
    }

    private func statusLine(for summary: SAScriptRunSummary) -> String {
        let errorsTitle = summary.errorCount > 0
            ? NSLocalizedString("Errors", comment: "Errors title")
            : NSLocalizedString("No errors", comment: "No errors title")
        let time = NSString(forTimeInterval: summary.executionTime) as String
        if summary.wasCancelled {
            if summary.queriesRun <= 1 {
                return String(format: NSLocalizedString("%@; Cancelled after %@", comment: "text showing a query was cancelled"),
                              errorsTitle, time)
            }
            return String(format: NSLocalizedString("%@; Cancelled in query %ld, after %@", comment: "text showing multiple queries were cancelled"),
                          errorsTitle, summary.queriesRun, time)
        }
        if summary.queriesRun <= 1 {
            let rows = summary.totalAffectedRows == 1
                ? String(format: NSLocalizedString("%@; 1 row affected", comment: "text showing one row has been affected by a single query"), errorsTitle)
                : String(format: NSLocalizedString("%@; %ld rows affected", comment: "text showing how many rows have been affected by a single query"),
                         errorsTitle, Int(summary.totalAffectedRows))
            return rows + String(format: NSLocalizedString(", taking %1$@", comment: "Custom Query : text appended to the “x row(s) affected” messages (for update/delete queries). $1 is a time interval"), time)
        }
        if summary.totalAffectedRows == 1 {
            return String(format: NSLocalizedString("%@; 1 row affected in total, by %ld queries taking %@", comment: "text showing one row has been affected by multiple queries"),
                          errorsTitle, summary.queriesRun, time)
        }
        return String(format: NSLocalizedString("%@; %ld rows affected in total, by %ld queries taking %@", comment: "text showing how many rows have been affected by multiple queries"),
                      errorsTitle, Int(summary.totalAffectedRows), summary.queriesRun, time)
    }
}
