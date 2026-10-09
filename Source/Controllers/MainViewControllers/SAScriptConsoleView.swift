//
//  SAScriptConsoleView.swift
//  Sequel Ace
//
//  The "Run All as Script" console that replaces the Query tab's result grid:
//  a small toolbar over a monospaced, read-only NSTextView. The text view is
//  fed incrementally from SAScriptConsoleModel.appended so multi-megabyte
//  output never goes through SwiftUI diffing.
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

/// Read-only, selectable, non-wrapping monospaced text view that appends
/// output chunks as the model publishes them.
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
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
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
        context.coordinator.bind(model: model, textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator {
        private var subscriptions = Set<AnyCancellable>()

        func bind(model: SAScriptConsoleModel, textView: NSTextView) {
            subscriptions.removeAll()
            model.appended
                .sink { [weak textView] chunk in
                    guard let textView, let storage = textView.textStorage else { return }
                    let wasAtBottom = Coordinator.isScrolledToBottom(textView)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: NSColor.textColor,
                    ]
                    storage.append(NSAttributedString(string: chunk, attributes: attributes))
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
        }

        private static func isScrolledToBottom(_ textView: NSTextView) -> Bool {
            guard let clipView = textView.enclosingScrollView?.contentView else { return true }
            return clipView.bounds.maxY >= textView.bounds.maxY - 24
        }
    }
}
