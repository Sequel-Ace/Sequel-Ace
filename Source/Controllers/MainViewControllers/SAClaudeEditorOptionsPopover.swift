//
//  SAClaudeEditorOptionsPopover.swift
//  Sequel Ace
//
//  The query editor's ⋯ options as a Claude popover card. The pop-up button
//  keeps its menu (so the items' shortcuts still work); a click shows this
//  popover instead, whose controls fire those same menu items or flip the
//  settings they're bound to. App target only.
//

import AppKit
import SwiftUI

/// The ⋯ pop-up button (DBView.xib): a click opens the popover instead of the menu.
@objc(SAClaudeEditorOptionsButton) final class SAClaudeEditorOptionsButton: NSPopUpButton {

    fileprivate weak var textView: NSTextView?
    private lazy var popover = SAClaudeEditorOptionsPopover(button: self)

    @objc(attachToButton:textView:)
    static func attach(to button: NSPopUpButton?, textView: NSTextView?) {
        (button as? SAClaudeEditorOptionsButton)?.textView = textView
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, menu != nil else { return }
        popover.toggle()
    }
}

/// Owns the NSPopover, its key/modifier monitors and the view model.
final class SAClaudeEditorOptionsPopover: NSObject, NSPopoverDelegate {

    private weak var button: SAClaudeEditorOptionsButton?
    private let model = SAClaudeEditorOptionsModel()
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: SAClaudeEditorOptionsView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        return popover
    }()
    private var monitors: [Any] = []

    private static func appearance(isDark: Bool) -> NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    init(button: SAClaudeEditorOptionsButton) {
        self.button = button
        super.init()
        model.close = { [weak self] in self?.popover.performClose(nil) }
        // The arrow and material follow a theme flip while the popover is open.
        model.appearanceDidChange = { [weak self] isDark in
            self?.popover.appearance = Self.appearance(isDark: isDark)
        }
    }

    func toggle() {
        guard let button else { return }
        if popover.isShown { popover.performClose(nil); return }
        removeMonitors()
        model.load(menu: button.menu, textView: button.textView)
        popover.appearance = Self.appearance(isDark: model.isDark)
        model.optionHeld = NSEvent.modifierFlags.contains(.option)   // ⌥ may already be down
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
        // ⌥ swaps Comment line for Comment query; a ⌘ shortcut (⌘R, ⌘]…) acts on the editor, so close first.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.model.optionHeld = event.modifierFlags.contains(.option)
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            // Esc closes; swallow it, or the ⋯ menu's Completion List item (Esc) would also fire in the main window.
            if event.keyCode == 53 { self.popover.performClose(nil); return nil }
            if event.modifierFlags.contains(.command) { self.popover.performClose(nil) }
            return event
        }) { monitors.append(monitor) }
    }

    func popoverDidClose(_ notification: Notification) {
        removeMonitors()
        model.optionHeld = false
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    deinit { removeMonitors() }
}

/// What the popover shows: the menu items behind each option, switch states, theme colours, the editor font.
final class SAClaudeEditorOptionsModel: ObservableObject {

    struct Colours {
        var surface = Color.clear, text = Color.primary, muted = Color.secondary
        var hairline = Color.gray, hover = Color.gray, tile = Color.gray, clay = Color.orange
    }

    @Published var switches: [SAClaudeEditorOption: Bool] = [:]
    @Published var enabled: Set<SAClaudeEditorOption> = []
    @Published var colours = Colours()
    @Published var fontDescription = ""
    @Published var optionHeld = false
    private(set) var isDark = true
    var close: () -> Void = {}
    /// Called when the theme's light/dark nature flips, so the popover can follow while open.
    var appearanceDidChange: ((Bool) -> Void)?
    private var appliedTheme: SAClaudeThemeColours?

    private var items: [SAClaudeEditorOption: NSMenuItem] = [:]
    private var defaultsObserver: NSObjectProtocol?

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) } }

    func load(menu: NSMenu?, textView: NSTextView?) {
        items.removeAll()
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { collect(submenu) }
                let key = (item.infoForBinding(.value)?[.observedKeyPath] as? String).map { $0.replacingOccurrences(of: "values.", with: "") }
                if let option = SAClaudeEditorOption.option(tag: item.tag, boundDefaultsKey: key, hasAction: item.action != nil), items[option] == nil {
                    items[option] = item
                }
            }
        }
        if let menu { collect(menu) }
        if let font = textView?.font {
            fontDescription = "\(font.displayName ?? font.fontName) \(Int(font.pointSize.rounded()))"
        }
        refresh()
    }

    private func refresh() {
        let defaults = UserDefaults.standard
        var states: [SAClaudeEditorOption: Bool] = [:]
        for option in SAClaudeEditorOption.allCases where option.isSwitch {
            if let key = option.defaultsKey { states[option] = defaults.bool(forKey: key) }
        }
        if states != switches { switches = states }
        // SPCustomQuery enables "Comment query" only while there is a current query (SPCustomQuery.m ~3125).
        let available = Set(items.filter { $0.value.isEnabled }.map(\.key))
        if available != enabled { enabled = available }

        // This runs on every app-wide defaults write; only rebuild the colours when the theme changed.
        let theme = SAClaudeThemeColours.from(defaults: defaults)
        guard theme != appliedTheme else { return }
        appliedTheme = theme
        let dark = SAClaudeGridChrome.isDark(theme.background)
        let darkChanged = dark != isDark
        isDark = dark
        let surface = SAClaudeStatusChrome.popupSurface(theme: theme)
        colours = Colours(surface: Color(nsColor: surface),
                          text: Color(nsColor: theme.text),
                          muted: Color(nsColor: SAClaudeStatusChrome.muted(theme: theme)),
                          hairline: Color(nsColor: SAClaudeStatusChrome.hairline(theme: theme)),
                          hover: Color(nsColor: SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: 0.08)),
                          tile: Color(nsColor: SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: 0.05)),
                          clay: Color(nsColor: SAClaudeStatusChrome.clay))
        if darkChanged { appearanceDidChange?(dark) }
    }

    /// The menu item's shortcut, e.g. "⌘]", for tooltips.
    func shortcut(for option: SAClaudeEditorOption) -> String? {
        guard let item = items[option], !item.keyEquivalent.isEmpty else { return nil }
        return SAClaudeEditorChrome.shortcutString(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

    /// Runs a command option (closing the popover first) or flips a switch.
    func activate(_ option: SAClaudeEditorOption) {
        if option.isSwitch { toggle(option); return }
        guard let item = items[option] else { return }
        close()
        fire(item)
    }

    private func toggle(_ option: SAClaudeEditorOption) {
        guard let key = option.defaultsKey else { return }
        let newValue = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(newValue, forKey: key)
        // Indent, auto-pair, uppercase and auto-help also update the open editor in gearMenuItemSelected:,
        // which reads the item's state — set it first, then fire the item as a menu click would.
        if let item = items[option], item.action != nil {
            item.state = newValue ? .on : .off
            // Not performActionForItem: it also runs the item's value binding, which would write the old value back.
            if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        }
        refresh()
    }

    private func fire(_ item: NSMenuItem) {
        guard let menu = item.menu else { return }
        let index = menu.index(of: item)
        guard index >= 0 else { return }
        menu.performActionForItem(at: index)
    }
}

/// The card.
struct SAClaudeEditorOptionsView: View {
    @ObservedObject var model: SAClaudeEditorOptionsModel

    var body: some View {
        let colours = model.colours
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(SAClaudeEditorOptionSection.all.enumerated()), id: \.offset) { index, section in
                if index > 0 { colours.hairline.frame(height: 1).padding(.vertical, 6) }
                Text(section.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colours.muted)
                    .padding(.horizontal, 4).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                sectionBody(section)
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(colours.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colours.hairline, lineWidth: 1))
    }

    @ViewBuilder private func sectionBody(_ section: SAClaudeEditorOptionSection) -> some View {
        switch section.options.first {
        case .previousHistory?:
            HStack(spacing: 6) {
                tile(.previousHistory, symbol: "arrow.up", showsTitle: true)
                tile(.nextHistory, symbol: "arrow.down", showsTitle: true)
            }.padding(.bottom, 4)
            switchRow(.historyReplacesContent)
            switchRow(.favoriteReplacesContent)
        case .shiftRight?:
            HStack(spacing: 6) {
                tile(.shiftRight, symbol: "increase.indent", showsTitle: false)
                tile(.shiftLeft, symbol: "decrease.indent", showsTitle: false)
                if model.optionHeld {
                    tile(.commentQuery, symbol: "text.bubble", showsTitle: false)
                } else {
                    tile(.commentLine, symbol: "text.bubble", showsTitle: false)
                }
            }
        case .completionList?:
            HStack(spacing: 6) {
                tile(.completionList, symbol: "list.bullet", showsTitle: true)
                tile(.completeDatabases, symbol: nil, showsTitle: true)
                tile(.completeTables, symbol: nil, showsTitle: true)
                tile(.completeFields, symbol: nil, showsTitle: true)
            }
        default:
            ForEach(section.options.filter(\.isSwitch), id: \.self) { switchRow($0) }
            fontRow
        }
    }

    private func tooltip(_ option: SAClaudeEditorOption) -> String {
        model.shortcut(for: option).map { "\(option.title)  \($0)" } ?? option.title
    }

    private func tile(_ option: SAClaudeEditorOption, symbol: String?, showsTitle: Bool) -> some View {
        Button { model.activate(option) } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12)) }
                if showsTitle { Text(option.title).font(.system(size: 12)).lineLimit(1) }
            }
            .foregroundColor(model.colours.text)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, showsTitle ? 6 : 0)
        }
        .buttonStyle(SAClaudeTileButtonStyle(rest: model.colours.tile, hover: model.colours.hover))
        .disabled(!model.enabled.contains(option))
        .help(tooltip(option))
        .accessibilityLabel(option.title)
    }

    private func switchRow(_ option: SAClaudeEditorOption) -> some View {
        let isOn = model.switches[option] ?? false
        return Button { model.activate(option) } label: {
            HStack {
                Text(option.title).font(.system(size: 12.5)).foregroundColor(model.colours.text)
                Spacer(minLength: 8)
                SAClaudeSwitch(isOn: isOn, on: model.colours.clay, off: model.colours.hairline)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel(option.title)
        .accessibilityValue(isOn ? Text(NSLocalizedString("ClaudeEditorOptionsOn", value: "On", comment: "Editor options popover: a switch's accessibility value when on"))
                                 : Text(NSLocalizedString("ClaudeEditorOptionsOff", value: "Off", comment: "Editor options popover: a switch's accessibility value when off")))
    }

    private var fontRow: some View {
        Button { model.activate(.editorFont) } label: {
            HStack {
                Text(SAClaudeEditorOption.editorFont.title).font(.system(size: 12.5)).foregroundColor(model.colours.text)
                Spacer(minLength: 8)
                Text(model.fontDescription).font(.system(size: 12)).foregroundColor(model.colours.muted)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(model.colours.muted)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel("\(SAClaudeEditorOption.editorFont.title), \(model.fontDescription)")
    }
}

/// A ghost tile: the resting tint, brighter on hover/press.
private struct SAClaudeTileButtonStyle: ButtonStyle {
    let rest: Color
    let hover: Color
    func makeBody(configuration: Configuration) -> some View {
        SAClaudeTileBody(configuration: configuration, rest: rest, hover: hover)
    }
}

private struct SAClaudeTileBody: View {
    let configuration: ButtonStyle.Configuration
    let rest: Color
    let hover: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovered || configuration.isPressed ? hover : rest))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

/// Claude's small switch: clay when on.
private struct SAClaudeSwitch: View {
    let isOn: Bool
    let on: Color
    let off: Color
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? on : off).frame(width: 26, height: 15)
            Circle().fill(Color.white).frame(width: 11, height: 11).padding(2)
        }
        .animation(.easeOut(duration: 0.12), value: isOn)
        .accessibilityHidden(true)
    }
}
