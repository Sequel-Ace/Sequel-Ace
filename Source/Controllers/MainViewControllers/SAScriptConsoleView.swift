//
//  SAScriptConsoleView.swift
//  Sequel Ace
//
//  The "Run All as Script" console that replaces the Query tab's result grid:
//  a Claude-style toolbar over a read-only NSTextView showing one block per
//  statement. The text view is fed incrementally from
//  SAScriptConsoleModel.eventsAppended (through SAScriptConsoleBlockBuilder) so
//  multi-megabyte output never goes through SwiftUI diffing. Its font and
//  colours follow the Query Editor's and preference changes live.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SAScriptConsoleView: View {

    let model: SAScriptConsoleModel
    let defaultSaveFileName: String

    @AppStorage(SAScriptConsoleModel.continueOnErrorDefaultsKey) private var continueOnError = false
    @StateObject private var chrome = SAConsoleChrome()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Toggle(NSLocalizedString("Continue on error", comment: "Script console: checkbox to keep running a script after a statement fails"),
                       isOn: $continueOnError)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color(nsColor: chrome.accentFill))
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: chrome.palette.buttonText))
                Spacer()
                SAConsoleGhostButton(glyph: .copy, title: NSLocalizedString("Copy all", comment: "Run All console: button that copies all output"), palette: chrome.palette, action: copyAll)
                SAConsoleGhostButton(glyph: .save, title: NSLocalizedString("Save…", comment: "Run All console: button that saves all output to a text file"), palette: chrome.palette, action: save)
                SAConsoleGhostButton(glyph: .clear, title: NSLocalizedString("Clear", comment: "Clear button"), palette: chrome.palette) { model.clear() }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Color(nsColor: chrome.palette.background))
            Rectangle().fill(Color(nsColor: chrome.palette.hairline)).frame(height: 1)
            SAScriptConsoleTextView(model: model)
        }
    }

    private func copyAll() {
        model.flush()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.text, forType: .string)
    }

    private func save() {
        model.flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultSaveFileName
        let output = model.text
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}

/// The editor-theme palette for the console's toolbar, refreshed on settings changes.
final class SAConsoleChrome: ObservableObject {
    @Published private(set) var palette = SAClaudeEditorChrome.palette(from: .standard)
    /// The accent fill, for the "Continue on error" switch; follows an accent change while the console is open.
    @Published private(set) var accentFill = SAClaudeEditorChrome.runFill
    private var observer: NSObjectProtocol?
    init() {
        SAClaudeAccent.observe(self) { $0.accentFill = SAClaudeEditorChrome.runFill }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            if palette != self?.palette { self?.palette = palette }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

/// A Claude ghost button: icon + label, 28pt tall, hover fill.
struct SAConsoleGhostButton: View {
    let glyph: SAClaudeGlyph
    let title: String
    let palette: SAClaudeEditorChrome.Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(nsImage: SAClaudeGlyphs.image(glyph, tint: palette.icon))
                Text(title).font(.system(size: 13)).foregroundColor(Color(nsColor: palette.buttonText))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color(nsColor: palette.hover) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Read-only, selectable, non-wrapping text view that shows the run as
/// statement blocks, appending them as the model publishes events.
private struct SAScriptConsoleTextView: NSViewRepresentable {

    let model: SAScriptConsoleModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 with non-contiguous layout and our own layout manager (its
        // drawBlockDecorations, called from SAScriptConsoleBlockTextView.drawBackground(in:),
        // draws the block separators and error tint): TextKit 2 handles very
        // wide, non-wrapping documents and very long single lines poorly.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let storage = NSTextStorage()
        let layoutManager = SAScriptConsoleLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        // No wrapping: rows are tab-separated lines; scroll horizontally instead.
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        // Text starts at the 14pt inset, like the block padding.
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = SAScriptConsoleBlockTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 14, height: 10)

        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.minSize = scrollView.contentSize
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        context.coordinator.bind(model: model, storage: storage, layoutManager: layoutManager, textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator {
        private var subscriptions = Set<AnyCancellable>()
        private var model: SAScriptConsoleModel?
        /// The text view does not own a text system built by hand; keep it alive here.
        private var storage: NSTextStorage?
        private var builder: SAScriptConsoleBlockBuilder?
        private var style: SAScriptConsoleStyle?
        /// The palette and style the console was last built with, to skip unchanged looks.
        private var look: [NSObject] = []

        /// The gap between blocks: each block's bottom and top padding (the layout
        /// manager draws the separator in its middle). The first block's top padding
        /// is the text container inset.
        private static let blockGap: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = 2 * SAScriptConsoleLayoutManager.blockPadding
            return style
        }()

        func bind(model: SAScriptConsoleModel, storage: NSTextStorage, layoutManager: SAScriptConsoleLayoutManager, textView: NSTextView) {
            subscriptions.removeAll()
            self.model = model
            self.storage = storage
            look = []
            refresh(textView: textView, layoutManager: layoutManager)

            model.eventsAppended
                .sink { [weak self, weak textView] events in
                    guard let self, let textView, let storage = self.storage else { return }
                    let wasAtBottom = Coordinator.isScrolledToBottom(textView)
                    storage.beginEditing()
                    self.append(events, to: storage)
                    storage.endEditing()
                    if wasAtBottom {
                        textView.scrollToEndOfDocument(nil)
                    }
                }
                .store(in: &subscriptions)
            model.cleared
                .sink { [weak self] in
                    guard let self, let storage = self.storage, let style = self.style else { return }
                    // The builder's ranges are absolute, so start a fresh one with the empty text.
                    self.builder = SAScriptConsoleBlockBuilder(style: style)
                    storage.beginEditing()
                    storage.deleteCharacters(in: NSRange(location: 0, length: storage.length))
                    storage.endEditing()
                }
                .store(in: &subscriptions)
            // Preferences → Query Editor (font, colours) and the theme switcher.
            // didChangeNotification fires for every default on any thread, so
            // coalesce onto the main queue; refresh skips unchanged looks.
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { [weak self, weak textView, weak layoutManager] _ in
                    guard let self, let textView, let layoutManager else { return }
                    self.refresh(textView: textView, layoutManager: layoutManager)
                }
                .store(in: &subscriptions)
        }

        /// Applies the editor's font and colours and, when they changed, rebuilds every block from the event log.
        func refresh(textView: NSTextView, layoutManager: SAScriptConsoleLayoutManager) {
            let font = SAScriptConsoleAppearance.resolve(from: .standard).font
            let newStyle = SAScriptConsoleStyle.from(defaults: .standard, font: font)
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let newLook: [NSObject] = [palette.background, newStyle.font, newStyle.text, newStyle.keyword, newStyle.string,
                                       newStyle.backtick, newStyle.number, newStyle.comment]
            guard newLook != look, let storage, let model else { return }
            look = newLook
            style = newStyle

            let background = palette.background
            textView.drawsBackground = true
            textView.backgroundColor = background
            textView.enclosingScrollView?.backgroundColor = background
            textView.enclosingScrollView?.appearance = SAClaudeGridChrome.scrollerAppearance(for: background)
            layoutManager.separatorColour = SAClaudeEditorChrome.derivedColour(text: newStyle.text, background: background, ratio: 0.04)
            layoutManager.errorTint = SAClaudeEditorChrome.derivedColour(text: layoutManager.errorEdge, background: background, ratio: 0.06)

            builder = SAScriptConsoleBlockBuilder(style: newStyle)
            storage.beginEditing()
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length))
            append(model.eventLog, to: storage)
            storage.endEditing()
            textView.needsDisplay = true
        }

        /// Appends the blocks for `events`; call between beginEditing() and endEditing().
        private func append(_ events: [SAScriptConsoleEvent], to storage: NSTextStorage) {
            guard let builder, !events.isEmpty else { return }
            let base = storage.length
            let built = builder.append(events)
            storage.append(built.text)
            // A failed block can start in an earlier chunk; the returned ranges are absolute.
            for range in built.errorRanges {
                let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
                if clamped.length > 0 { storage.addAttribute(.saConsoleBlockError, value: true, range: clamped) }
            }
            built.text.enumerateAttribute(.saConsoleBlockStart, in: NSRange(location: 0, length: built.text.length), options: []) { value, range, _ in
                guard (value as? Bool) == true, base + range.location > 0 else { return }
                let paragraph = storage.mutableString.paragraphRange(for: NSRange(location: base + range.location, length: 0))
                storage.addAttribute(.paragraphStyle, value: Coordinator.blockGap, range: paragraph)
            }
        }

        private static func isScrolledToBottom(_ textView: NSTextView) -> Bool {
            guard let clipView = textView.enclosingScrollView?.contentView else { return true }
            return clipView.bounds.maxY >= textView.bounds.maxY - 24
        }
    }
}
