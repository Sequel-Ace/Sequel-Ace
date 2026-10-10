//
//  SAScriptConsoleView.swift
//  Sequel Ace
//
//  The "Run All as Script" console that replaces the Query tab's result grid:
//  a small toolbar over a read-only NSTextView. The text view is fed
//  incrementally from SAScriptConsoleModel.appended so multi-megabyte output
//  never goes through SwiftUI diffing. Its font and colours come from
//  SAScriptConsoleAppearance (the Query Editor's by default) and follow
//  preference changes live.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SAScriptConsoleView: View {

    let model: SAScriptConsoleModel
    let defaultSaveFileName: String

    @AppStorage(SAScriptConsoleModel.continueOnErrorDefaultsKey) private var continueOnError = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle(NSLocalizedString("Continue on error", comment: "Script console: checkbox to keep running a script after a statement fails"),
                       isOn: $continueOnError)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(NSLocalizedString("Copy All", comment: "Script console: button that copies all output to the clipboard")) {
                    copyAll()
                }
                Button(NSLocalizedString("Save Output…", comment: "Script console: button that saves all output to a text file")) {
                    save()
                }
                Button(NSLocalizedString("Clear", comment: "Clear button")) {
                    model.clear()
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            Divider()
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

/// Read-only, selectable, non-wrapping text view that appends output chunks
/// as the model publishes them.
private struct SAScriptConsoleTextView: NSViewRepresentable {

    let model: SAScriptConsoleModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 with non-contiguous layout: scrollableTextView() is TextKit 2
        // on macOS 13+, which handles very wide, non-wrapping documents and very
        // long single lines poorly.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(usingTextLayoutManager: false)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // No wrapping: rows are tab-separated lines; scroll horizontally instead.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.minSize = scrollView.contentSize
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        textView.string = model.text
        context.coordinator.apply(SAScriptConsoleAppearance.resolve(from: .standard), to: textView)
        context.coordinator.bind(model: model, textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator {
        private var subscriptions = Set<AnyCancellable>()
        private var appearance = SAScriptConsoleAppearance.fallback
        private var hasAppliedAppearance = false

        func bind(model: SAScriptConsoleModel, textView: NSTextView) {
            subscriptions.removeAll()
            model.appended
                .sink { [weak self, weak textView] chunk in
                    guard let self, let textView, let storage = textView.textStorage else { return }
                    let wasAtBottom = Coordinator.isScrolledToBottom(textView)
                    storage.append(NSAttributedString(string: chunk, attributes: self.textAttributes))
                    if wasAtBottom {
                        textView.scrollToEndOfDocument(nil)
                    }
                }
                .store(in: &subscriptions)
            model.cleared
                .sink { [weak textView] in
                    textView?.string = ""
                }
                .store(in: &subscriptions)
            // Preferences → Query Editor (font, colours, Script Output override).
            // didChangeNotification fires for every default on any thread, so
            // coalesce onto the main queue; apply(_:to:) skips unchanged looks.
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { [weak self, weak textView] _ in
                    guard let self, let textView else { return }
                    self.apply(SAScriptConsoleAppearance.resolve(from: .standard), to: textView)
                }
                .store(in: &subscriptions)
        }

        /// Applies the font and colours to the view and restyles the text already shown.
        func apply(_ newAppearance: SAScriptConsoleAppearance, to textView: NSTextView) {
            guard !hasAppliedAppearance || newAppearance != appearance else { return }
            appearance = newAppearance
            hasAppliedAppearance = true
            textView.font = newAppearance.font
            textView.textColor = newAppearance.textColor
            textView.backgroundColor = newAppearance.backgroundColor
            textView.enclosingScrollView?.backgroundColor = newAppearance.backgroundColor
            textView.typingAttributes = textAttributes
            if let storage = textView.textStorage, storage.length > 0 {
                storage.beginEditing()
                storage.addAttributes(textAttributes, range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
            }
        }

        private var textAttributes: [NSAttributedString.Key: Any] {
            [.font: appearance.font, .foregroundColor: appearance.textColor]
        }

        private static func isScrolledToBottom(_ textView: NSTextView) -> Bool {
            guard let clipView = textView.enclosingScrollView?.contentView else { return true }
            return clipView.bounds.maxY >= textView.bounds.maxY - 24
        }
    }
}
