import AppKit
import SwiftUI

struct SASQLiteQueryEditor: NSViewRepresentable {
    @ObservedObject var model: SASQLiteWorkspaceModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true

        let editor = SASQLiteQueryEditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 170))
        editor.string = model.sql
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFindPanel = true
        editor.focusRingType = .none
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.maxSize = NSSize(width: 100_000, height: 10_000_000)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 100_000, height: 10_000_000)
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.setAccessibilityLabel(NSLocalizedString("SQLite Query Editor", comment: "Accessibility label for SQLite SQL editor"))
        editor.delegate = context.coordinator
        editor.runQuery = { [weak model] mode in model?.runSQL(mode) }
        scroll.documentView = editor
        scroll.verticalRulerView = NoodleLineNumberView(scrollView: scroll)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        model.queryEditor = editor
        context.coordinator.observePreferences(for: editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SASQLiteQueryEditorTextView,
              !editor.string.utf8.elementsEqual(model.sql.utf8) else { return }
        editor.string = model.sql
        context.coordinator.style(editor)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: SASQLiteWorkspaceModel
        private var preferences: NSObjectProtocol?
        private var tokens: [SASQLiteSQLStyle.Token] = []
        private var highlightedStatement: NSRange?

        init(_ model: SASQLiteWorkspaceModel) { self.model = model }

        deinit {
            if let preferences { NotificationCenter.default.removeObserver(preferences) }
        }

        func observePreferences(for editor: SASQLiteQueryEditorTextView) {
            applyTheme(to: editor)
            preferences = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self, weak editor] _ in
                MainActor.assumeIsolated {
                    if let editor { self?.applyTheme(to: editor) }
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? SASQLiteQueryEditorTextView else { return }
            model.sql = editor.string
            style(editor)
            updateSelection(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let editor = notification.object as? SASQLiteQueryEditorTextView {
                updateSelection(editor)
                highlightStatement(in: editor)
            }
        }

        func style(_ editor: SASQLiteQueryEditorTextView) {
            guard let layout = editor.layoutManager else { return }
            let length = (editor.string as NSString).length
            let range = NSRange(location: 0, length: length)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            highlightedStatement = nil
            // Keep typing and pasting responsive for very large SQL scripts.
            tokens = length <= 120_000 ? SASQLiteSQLStyle.tokens(in: editor.string) : []
            if UserDefaults.standard.bool(forKey: SPCustomQueryEnableSyntaxHighlighting) {
                let colors: [SASQLiteSQLStyle.Kind: NSColor] = [
                    .keyword: color(SPCustomQueryEditorSQLKeywordColor, fallback: .systemBlue),
                    .string: color(SPCustomQueryEditorQuoteColor, fallback: .systemRed),
                    .identifier: color(SPCustomQueryEditorBacktickColor, fallback: .systemPurple),
                    .number: color(SPCustomQueryEditorNumericColor, fallback: .systemBlue),
                    .parameter: color(SPCustomQueryEditorVariableColor, fallback: .systemPurple),
                    .lineComment: color(SPCustomQueryEditorCommentColor, fallback: .secondaryLabelColor),
                    .blockComment: color(SPCustomQueryEditorCommentColor, fallback: .secondaryLabelColor)
                ]
                for token in tokens {
                    if let color = colors[token.kind] {
                        layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
                    }
                }
            }
            highlightStatement(in: editor)
        }

        private func highlightStatement(in editor: SASQLiteQueryEditorTextView) {
            guard let layout = editor.layoutManager,
                  UserDefaults.standard.bool(forKey: SPCustomQueryHighlightCurrentQuery),
                  !tokens.isEmpty else { return }
            let range = SASQLiteSQLStyle.currentStatement(in: editor.string, at: editor.selectedRange().location, tokens: tokens)
            guard range != highlightedStatement else { return }
            if let previous = highlightedStatement {
                layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: previous)
            }
            highlightedStatement = range
            if let range {
                let background = color(SPCustomQueryEditorHighlightQueryColor, fallback: .selectedTextBackgroundColor)
                layout.addTemporaryAttribute(.backgroundColor, value: background, forCharacterRange: range)
            }
        }

        private func updateSelection(_ editor: SASQLiteQueryEditorTextView) {
            let text = editor.string as NSString
            let range = editor.selectedRange()
            model.selectedSQL = range.length > 0 && NSMaxRange(range) <= text.length ? text.substring(with: range) : ""
        }

        private func applyTheme(to editor: SASQLiteQueryEditorTextView) {
            let defaults = UserDefaults.standard
            editor.font = SAArchiving.font(from: defaults.data(forKey: SPCustomQueryEditorFont)) ??
                .monospacedSystemFont(ofSize: 13, weight: .regular)
            editor.textColor = color(SPCustomQueryEditorTextColor, fallback: .textColor)
            editor.backgroundColor = color(SPCustomQueryEditorBackgroundColor, fallback: .textBackgroundColor)
            editor.insertionPointColor = color(SPCustomQueryEditorCaretColor, fallback: .textColor)
            editor.selectedTextAttributes = [.backgroundColor: color(SPCustomQueryEditorSelectionColor, fallback: .selectedTextBackgroundColor)]
            style(editor)
        }

        private func color(_ key: String, fallback: NSColor) -> NSColor {
            let defaults = UserDefaults.standard
            let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)[key] as? Data
            return SAArchiving.color(from: defaults.data(forKey: key)) ?? SAArchiving.color(from: registered) ?? fallback
        }
    }
}

@objc final class SASQLiteQueryEditorTextView: NSTextView {
    var runQuery: ((SASQLiteWorkspaceModel.QueryAction) -> Void)?

    func currentSQLiteStatement() -> String {
        guard let range = SASQLiteSQLStyle.currentStatement(in: string, at: selectedRange().location) else { return "" }
        return (string as NSString).substring(with: range)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if window?.firstResponder === self, let runQuery {
            if event.charactersIgnoringModifiers == "r", flags == [.command] || flags == [.command, .option] {
                let primaryRunsAll = UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll)
                runQuery(primaryRunsAll == (flags == [.command]) ? .all : .current)
                return true
            }
            if event.charactersIgnoringModifiers == "e", flags == [.command, .option] {
                runQuery(.explain)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc(handleFormatBundle:responder:)
    static func handleFormatBundle(_ sender: Any?, responder: Any?) -> Bool {
        guard let editor = responder as? SASQLiteQueryEditorTextView,
              let menuItem = sender as? NSMenuItem,
              let command = menuItem.representedObject as? [String: String],
              command[SPBundleFileUUIDKey] == "36E1F94D-D6C4-460A-A663-C694AF85E099" else { return false }
        editor.formatSQLiteSQL(menuItem)
        return true
    }

    @objc func formatSQLiteSQL(_ sender: Any?) {
        let selected = selectedRange()
        let source = string as NSString
        guard let range = selected.length > 0 ? selected : SASQLiteSQLStyle.currentStatement(in: string, at: selected.location),
              range.length > 0, NSMaxRange(range) <= source.length else { return }
        let original = source.substring(with: range)
        let formatted = SASQLiteSQLStyle.format(original)
        guard !original.utf8.elementsEqual(formatted.utf8), shouldChangeText(in: range, replacementString: formatted) else { return }
        replaceCharacters(in: range, with: formatted)
        didChangeText()
        let newLength = (formatted as NSString).length
        if selected.length > 0 {
            setSelectedRange(NSRange(location: range.location, length: newLength))
        } else {
            setSelectedRange(NSRange(location: min(selected.location, range.location + newLength), length: 0))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = (super.menu(for: event)?.copy() as? NSMenu) ?? NSMenu()
        menu.addItem(.separator())
        let item = NSMenuItem(title: NSLocalizedString("Format SQL", comment: "Format the current SQLite query or selection"),
                              action: #selector(formatSQLiteSQL(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }
}

struct SASQLiteRunControl: NSViewRepresentable {
    @ObservedObject var model: SASQLiteWorkspaceModel
    @AppStorage(SPQueryPrimaryControlRunsAll) private var runsAll = false
    let resetPage: () -> Void

    func makeNSView(context: Context) -> SPComboPopupButton {
        let button = SPComboPopupButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = context.coordinator
        button.action = #selector(Coordinator.runPrimary(_:))
        return button
    }

    func updateNSView(_ button: SPComboPopupButton, context: Context) {
        context.coordinator.parent = self
        let hasSelection = !model.selectedSQL.isEmpty
        let shortTitle = runsAll
            ? NSLocalizedString("Run All", comment: "Query run button")
            : hasSelection ? NSLocalizedString("Run Selection", comment: "Query run button")
                : NSLocalizedString("Run Current", comment: "Query run button")
        let currentTitle = hasSelection
            ? NSLocalizedString("Run Selected Text", comment: "Query run menu")
            : NSLocalizedString("Run Current Query", comment: "Query run menu")
        let allTitle = NSLocalizedString("Run All Queries", comment: "Query run menu")
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: shortTitle, action: nil, keyEquivalent: "")
        titleItem.isHidden = true
        menu.addItem(titleItem)
        let current = context.coordinator.item(currentTitle, action: #selector(Coordinator.runCurrent(_:)), key: "r",
                                               modifiers: runsAll ? [.command, .option] : [.command])
        let all = context.coordinator.item(allTitle, action: #selector(Coordinator.runAll(_:)), key: "r",
                                           modifiers: runsAll ? [.command] : [.command, .option])
        menu.addItem(runsAll ? all : current)
        menu.addItem(.separator())
        menu.addItem(runsAll ? current : all)
        menu.addItem(context.coordinator.item(NSLocalizedString("Switch Default", comment: "Query run menu"),
                                             action: #selector(Coordinator.switchDefault(_:))))
        menu.addItem(.separator())
        menu.addItem(context.coordinator.item(NSLocalizedString("Explain Current Query", comment: "Query run menu"),
                                             action: #selector(Coordinator.explain(_:)), key: "e", modifiers: [.command, .option]))
        button.menu = menu
        button.selectItem(at: 0)
        button.isEnabled = !model.busy && !model.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SASQLiteRunControl
        init(_ parent: SASQLiteRunControl) { self.parent = parent }

        func item(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = modifiers
            return item
        }

        @objc func runPrimary(_ sender: Any?) { run(parent.runsAll ? .all : .current) }
        @objc func runCurrent(_ sender: Any?) { run(.current) }
        @objc func runAll(_ sender: Any?) { run(.all) }
        @objc func explain(_ sender: Any?) { run(.explain) }

        @objc func switchDefault(_ sender: Any?) {
            UserDefaults.standard.set(!parent.runsAll, forKey: SPQueryPrimaryControlRunsAll)
        }

        private func run(_ mode: SASQLiteWorkspaceModel.QueryAction) {
            parent.resetPage()
            parent.model.runSQL(mode)
        }
    }
}
