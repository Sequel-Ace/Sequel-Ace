//
//  SAClaudeSettingsWindow.swift
//  Sequel Ace
//
//  The Settings window's content in the Claude look: a sidebar of the nine panes (SAClaudeSettingsCatalog) and the
//  selected pane — its title, then its sections of cards — scrolling inside the window, drawn with the row views of
//  SAClaudeSettingsControls.swift, the `.app` palette and one SAClaudeSettingsStore per window.
//
//  SPPreferenceController keeps the window and every old pane controller (their actions, sheets and outside callers).
//  The host makes an NSHostingView the window's content and parks the old XIB pane views beside it, hidden, so pane
//  code that reaches its window through `view.window` (sheets, the font panel's target) still finds this window.
//
//  Plain rows show their standard control. Custom rows, dynamic pills and rows whose control must call pane code take
//  theirs from the window's SAClaudeSettingsViewRegistry, which SAClaudeSettingsPanes.register(in:) fills; a row with
//  nothing registered shows a quiet placeholder. A registration can also replace a whole row (to add content under it)
//  or a whole section.
//
//  App target only.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Host

/// Installs the Settings content in SPPreferenceController's window and routes outside requests to a pane and row.
@objc(SAClaudeSettingsWindowHost)
@MainActor
final class SAClaudeSettingsWindowHost: NSObject {

    static let defaultContentSize = NSSize(width: 760, height: 560)
    static let minimumContentSize = NSSize(width: 640, height: 420)
    static let frameAutosaveName = "SAClaudeSettingsWindow"
    /// The hidden view holding the old XIB pane views.
    static let legacyPaneParkingIdentifier = NSUserInterfaceItemIdentifier("SAClaudeSettingsLegacyPanes")

    let model = SAClaudeSettingsWindowModel()
    let store: SAClaudeSettingsStore
    let palette: SAClaudeSwiftUIPalette
    let registry = SAClaudeSettingsViewRegistry()
    private(set) weak var window: NSWindow?
    private(set) weak var controller: SPPreferenceController?
    /// The old pane controllers by toolbar identifier (they stay loaded; their views are parked).
    let legacyPanes: [String: SPPreferencePane & SPPreferencePaneProtocol]
    private let legacyPaneOrder: [SPPreferencePane & SPPreferencePaneProtocol]
    private(set) var hostingView: NSView?
    private(set) var legacyPaneParking: NSView?

    /// Creates the host for `controller`'s window and installs the content (call once, after the nib has loaded).
    @objc(installIn:controller:)
    static func install(in window: NSWindow, controller: SPPreferenceController) -> SAClaudeSettingsWindowHost {
        let host = SAClaudeSettingsWindowHost(window: window, controller: controller,
                                              legacyPanes: controller.legacyPreferencePanes, store: SAClaudeSettingsStore())
        host.install()
        return host
    }

    /// The pieces without installing them: registrations made before `install()` are in place when the content is
    /// first drawn (a harness passes a store over a scratch suite).
    init(window: NSWindow, controller: SPPreferenceController?, legacyPanes: [SPPreferencePane & SPPreferencePaneProtocol],
         store: SAClaudeSettingsStore) {
        self.window = window
        self.controller = controller
        self.store = store
        palette = SAClaudeSwiftUIPalette(source: .app)
        legacyPaneOrder = legacyPanes
        var byIdentifier: [String: SPPreferencePane & SPPreferencePaneProtocol] = [:]
        for pane in legacyPanes { byIdentifier[pane.preferencePaneIdentifier()] = pane }
        self.legacyPanes = byIdentifier
        super.init()
        SAClaudeSettingsPanes.register(in: registry)
        model.selectionHandler = { [weak self] pane in self?.select(pane, refreshingAlways: false) }
    }

    /// Titles the window "Settings", drops the toolbar, sizes it (≈760 × 560, at least 640 × 420, resizable, its frame
    /// remembered), parks the old pane views and shows the SwiftUI content on the first pane.
    func install() {
        guard let window, hostingView == nil else { return }
        // NSWindowController would cascade the window from the last one it placed after this, moving a remembered frame.
        controller?.shouldCascadeWindows = false
        window.title = NSLocalizedString("ClaudeSettings.ui.windowTitle", comment: "Claude Settings: the title of the Settings window (was \"Preferences\")")
        window.toolbar = nil
        window.styleMask.insert(.resizable)
        let unlimited = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Preferences.xib caps the window at 1500 × 700.
        window.maxSize = unlimited
        window.contentMaxSize = unlimited
        window.maxFullScreenContentSize = unlimited
        window.contentMinSize = Self.minimumContentSize
        window.minFullScreenContentSize = Self.minimumContentSize

        let container = NSView(frame: NSRect(origin: .zero, size: Self.defaultContentSize))
        container.autoresizesSubviews = true

        // The old pane views stay in the window (hidden, never laid out): their code finds its window through
        // `view.window` for sheets and the font panel, and Tasks 4–5 move the cipher and files tables out of them.
        let parking = NSView(frame: .zero)
        parking.identifier = Self.legacyPaneParkingIdentifier
        parking.isHidden = true
        parking.autoresizesSubviews = false
        for pane in legacyPaneOrder {
            guard let view = pane.preferencePaneView() else { continue }
            view.removeFromSuperview()
            parking.addSubview(view)
        }
        container.addSubview(parking)

        let root = SAClaudeSettingsRootView(model: model, palette: palette, store: store, registry: registry, host: self)
        let hosting = NSHostingView(rootView: root)
        // The window sizes the content, never the other way round.
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        hostingView = hosting
        legacyPaneParking = parking

        window.contentView = container
        window.setContentSize(Self.defaultContentSize)
        window.center()
        window.setFrameAutosaveName(Self.frameAutosaveName)
        // A remembered frame wins over the default size.
        window.setFrameUsingName(Self.frameAutosaveName)

        refreshLegacyPanes(for: model.selectedPane)

        // The generic Claude sheet skin claims this window (SPPreferenceController is one of its auxiliary owners)
        // whenever it becomes key: the theme's light/dark appearance and surface on the window, the surface view at the
        // back of the container, and every AppKit control outside the hosting view (here the parked XIB panes)
        // restyled. Claim it now so the first show already has the right appearance.
        SAClaudeSheetStyler.consider(window)
    }

    // MARK: Routing

    /// Opens `pane` (a `SAClaudeSettingsPaneID` raw value) and scrolls to `revealRowID`, briefly tinting it; the row
    /// decides the pane when it is known. With `regrantStaleFiles` (the launch alert and the file prompts) a request
    /// for the accessible-files row also opens the Files pane's re-select panel for the stale entries, once the list
    /// is disclosed — the only way that panel opens by itself (`SAClaudeSettingsCatalog.regrantsStaleFiles`).
    /// Doesn't show the window (SPPreferenceController's `showSettingsPane:…` does).
    @objc(showPane:revealRowID:regrantStaleFiles:)
    func show(pane: String?, revealRowID: String?, regrantStaleFiles: Bool) {
        guard let destination = SAClaudeSettingsCatalog.destination(pane: pane, rowID: revealRowID) else {
            NSLog("Settings: no pane %@ / row %@", pane ?? "nil", revealRowID ?? "nil")
            return
        }
        // As `displayPreferencePane:` did, an outside request refreshes the old pane controllers even on the same pane.
        select(destination.pane, refreshingAlways: true)
        model.reveal(destination, regrantStaleFiles: regrantStaleFiles)
        if SAClaudeSettingsCatalog.regrantsStaleFiles(destination, requested: regrantStaleFiles),
           let files = legacyPanes[SAClaudeSettingsCatalog.LegacyPane.file.rawValue] as? SPFilePreferencePane {
            // Next turn: the reveal has disclosed the list, so the panel opens over the highlighted stale entries.
            DispatchQueue.main.async { files.regrantStaleFiles() }
        }
    }

    @objc(showPane:revealRowID:)
    func show(pane: String, revealRowID: String?) {
        show(pane: pane, revealRowID: revealRowID, regrantStaleFiles: false)
    }

    /// `displayPreferencePane:` with an old toolbar item's identifier (nil: the first pane).
    @objc(showLegacyPaneIdentifier:)
    func showLegacyPane(_ identifier: String?) {
        let destination = SAClaudeSettingsCatalog.destination(forLegacyPane: identifier)
        show(pane: destination.pane.rawValue, revealRowID: destination.rowID, regrantStaleFiles: false)
    }

    /// Writes the edit in progress — a Claude field's (it would otherwise be lost when its view goes away) and an
    /// AppKit field editor's — before the window closes or the pane changes.
    @objc func commitEditing() {
        model.requestCommit()
        if let window, window.firstResponder is NSText {
            window.makeFirstResponder(nil)
        }
    }

    private func select(_ pane: SAClaudeSettingsPaneID, refreshingAlways: Bool) {
        let changes = pane != model.selectedPane
        if changes {
            commitEditing()
            model.select(pane)
        }
        if changes || refreshingAlways { refreshLegacyPanes(for: pane) }
    }

    /// The old pane controllers' `preferencePaneWillBeShown` for the panes `pane`'s rows came from (fonts, favourites,
    /// SSH lists and ciphers, bookmarks, MCP status), as the toolbar ran it when their pane was shown.
    private func refreshLegacyPanes(for pane: SAClaudeSettingsPaneID) {
        for legacy in SAClaudeSettingsCatalog.legacyPanes(for: pane) {
            legacyPanes[legacy.rawValue]?.preferencePaneWillBeShown()
        }
    }

    // MARK: Menu

    /// Retitles the app menu item that opens this window "Settings…" (MainMenu.xib keeps "Preferences..."; ⌘, is
    /// unchanged). Call once at launch.
    @objc static func applySettingsMenuTitle() {
        guard let item = NSApp.mainMenu.flatMap({ menuItem(in: $0, action: NSSelectorFromString("openPreferences:")) }) else { return }
        item.title = NSLocalizedString("ClaudeSettings.ui.menuItem", comment: "Claude Settings: the app menu item that opens the Settings window (was \"Preferences...\")")
    }

    private static func menuItem(in menu: NSMenu, action: Selector) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action { return item }
            if let submenu = item.submenu, let found = menuItem(in: submenu, action: action) { return found }
        }
        return nil
    }
}

// MARK: - Model

/// A request to open the window on a pane and row. `serial` tells repeated requests apart: act on each once.
struct SAClaudeSettingsReveal: Equatable {
    let serial: Int
    let pane: SAClaudeSettingsPaneID
    let rowID: String?
    /// The request came from a file prompt that asks for stale files to be re-granted (the accessible-files row acts).
    let regrantStaleFiles: Bool
}

/// The window's state: the selected pane, the one open (i), the last reveal request and the row briefly tinted by it.
@MainActor
final class SAClaudeSettingsWindowModel: ObservableObject {
    @Published private(set) var selectedPane: SAClaudeSettingsPaneID = .appearance
    /// The one row whose (i) explanation is open in the window.
    @Published var openInfoRowID: String?
    @Published private(set) var reveal: SAClaudeSettingsReveal?
    @Published private(set) var highlightedRowID: String?

    /// Sent to the window's Claude fields by `requestCommit()` (`claudeCommitRequests`).
    let commitRequests: AnyPublisher<Void, Never>
    private let commitSubject = PassthroughSubject<Void, Never>()
    /// Switching panes from the sidebar goes through the host (it commits the edit and refreshes the old panes).
    var selectionHandler: ((SAClaudeSettingsPaneID) -> Void)?
    /// The row the pane scrolls to once it is on screen.
    private var pendingScroll: (pane: SAClaudeSettingsPaneID, rowID: String)?
    private var revealSerial = 0

    static let highlightDuration: TimeInterval = 1.6

    init() {
        commitRequests = commitSubject.eraseToAnyPublisher()
    }

    /// The sidebar's choice.
    func requestSelection(_ pane: SAClaudeSettingsPaneID) {
        if let selectionHandler { selectionHandler(pane) } else { select(pane) }
    }

    func select(_ pane: SAClaudeSettingsPaneID) {
        guard pane != selectedPane else { return }
        openInfoRowID = nil
        selectedPane = pane
    }

    func requestCommit() {
        commitSubject.send()
    }

    func toggleInfo(_ rowID: String) {
        openInfoRowID = openInfoRowID == rowID ? nil : rowID
    }

    func reveal(_ destination: SAClaudeSettingsCatalog.Destination, regrantStaleFiles: Bool) {
        select(destination.pane)
        revealSerial += 1
        let serial = revealSerial
        reveal = SAClaudeSettingsReveal(serial: serial, pane: destination.pane, rowID: destination.rowID,
                                        regrantStaleFiles: regrantStaleFiles)
        guard let rowID = destination.rowID else {
            pendingScroll = nil
            highlightedRowID = nil
            return
        }
        pendingScroll = (destination.pane, rowID)
        highlightedRowID = rowID
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightDuration) { [weak self] in
            guard let self, self.reveal?.serial == serial else { return }
            self.highlightedRowID = nil
        }
    }

    /// The row `pane` should scroll to, once.
    func takePendingScroll(for pane: SAClaudeSettingsPaneID) -> String? {
        guard let pendingScroll, pendingScroll.pane == pane else { return nil }
        self.pendingScroll = nil
        return pendingScroll.rowID
    }
}

// MARK: - Registry

/// What a custom row, a dynamic pill or a pane-code row shows, registered per window by SAClaudeSettingsPanes.
/// Lookups for a row's control, in order: a registration for the row's id; the standard control for a plain row
/// (`SAClaudeSettingStandardControl.handles`); one for its custom control or dynamic source; else the placeholder.
@MainActor
final class SAClaudeSettingsViewRegistry {
    typealias RowBuilder = (SAClaudeSettingsRowContext) -> AnyView
    typealias SectionBuilder = (SAClaudeSettingsSectionContext) -> AnyView

    private var customControls: [SAClaudeSettingCustom: RowBuilder] = [:]
    private var dynamicControls: [String: RowBuilder] = [:]
    private var rowControls: [String: RowBuilder] = [:]
    private var rows: [String: RowBuilder] = [:]
    private var sections: [String: SectionBuilder] = [:]

    /// The control (at the row's right) of every row with this custom control.
    func registerControl<V: View>(for custom: SAClaudeSettingCustom,
                                  @ViewBuilder _ build: @escaping (SAClaudeSettingsRowContext) -> V) {
        customControls[custom] = { AnyView(build($0)) }
    }

    /// The control of every pill with this dynamic source ("favorites", "encodings", "sshConfig", "knownHosts").
    func registerControl<V: View>(forDynamicSource source: String,
                                  @ViewBuilder _ build: @escaping (SAClaudeSettingsRowContext) -> V) {
        dynamicControls[source] = { AnyView(build($0)) }
    }

    /// The control of one row, even a plain one (it wins over the standard control: e.g. the MCP port).
    func registerControl<V: View>(forRow rowID: String, @ViewBuilder _ build: @escaping (SAClaudeSettingsRowContext) -> V) {
        rowControls[rowID] = { AnyView(build($0)) }
    }

    /// The whole row — for one that adds content under itself (a disclosed list, a status line). Start from
    /// `context.standardRow { control }` to keep the row's look and (i).
    func registerRow<V: View>(_ rowID: String, @ViewBuilder _ build: @escaping (SAClaudeSettingsRowContext) -> V) {
        rows[rowID] = { AnyView(build($0)) }
    }

    /// The whole section, heading and card (`context.heading`, `context.row(_:)` give the standard pieces).
    func registerSection<V: View>(_ sectionID: String, @ViewBuilder _ build: @escaping (SAClaudeSettingsSectionContext) -> V) {
        sections[sectionID] = { AnyView(build($0)) }
    }

    /// A registered control for `row` (its own id first), nil when there is none.
    func registeredControl(for row: SAClaudeSettingRow) -> RowBuilder? {
        if let build = rowControls[row.id] { return build }
        switch row.control {
        case .custom(let custom): return customControls[custom]
        case .choice(_, .dynamic(let source)): return dynamicControls[source]
        default: return nil
        }
    }

    func hasRowControl(_ rowID: String) -> Bool { rowControls[rowID] != nil }
    func rowBuilder(for rowID: String) -> RowBuilder? { rows[rowID] }
    func sectionBuilder(for sectionID: String) -> SectionBuilder? { sections[sectionID] }
}

/// What a row builder gets: the row, its (i) state, the window's model and host (the preference controller and its
/// pane controllers through `controller`).
struct SAClaudeSettingsRowContext {
    let row: SAClaudeSettingRow
    let infoOpen: Bool
    let toggleInfo: () -> Void
    let model: SAClaudeSettingsWindowModel
    let registry: SAClaudeSettingsViewRegistry
    weak var host: SAClaudeSettingsWindowHost?

    @MainActor var controller: SPPreferenceController? { host?.controller }

    /// The row's standard look — name, (i), description, dependent indent and dimming — with `control` at its right.
    func standardRow<C: View>(@ViewBuilder control: @escaping () -> C) -> SAClaudeSettingsRowView<C> {
        SAClaudeSettingsRowView(row: row, infoOpen: infoOpen, onInfo: toggleInfo, content: control)
    }
}

/// What a section builder gets, with the standard heading and rows to compose from.
struct SAClaudeSettingsSectionContext {
    let section: SAClaudeSettingsSection
    let model: SAClaudeSettingsWindowModel
    let registry: SAClaudeSettingsViewRegistry
    weak var host: SAClaudeSettingsWindowHost?

    @MainActor var controller: SPPreferenceController? { host?.controller }

    /// The small secondary heading (empty for an untitled section).
    var heading: SAClaudeSettingsSectionHeading { SAClaudeSettingsSectionHeading(titleKey: section.titleKey) }

    /// One row as the window shows it unregistered at section level (its registrations, highlight and scroll id).
    func row(_ row: SAClaudeSettingRow) -> SAClaudeSettingsRowSlot {
        SAClaudeSettingsRowSlot(row: row, model: model, registry: registry, host: host)
    }

    /// The section as the window shows it: heading, then a card of its rows with hairlines between them.
    var standard: SAClaudeSettingsStandardSection {
        SAClaudeSettingsStandardSection(context: self)
    }
}

// MARK: - Views

enum SAClaudeSettingsWindowMetrics {
    /// The spec's ≈190pt, widened so "Startup and connections" (149pt at 13pt) fits beside its icon untruncated.
    static let sidebarWidth: CGFloat = 210
    static let sidebarPadding: CGFloat = 8
    static let sidebarRowHeight: CGFloat = 28
    static let sidebarRowSpacing: CGFloat = 2
    static let sidebarRowRadius: CGFloat = 8
    static let sidebarIconWidth: CGFloat = 18
    static let sidebarFont = Font.system(size: 13)
    static let sidebarIconFont = Font.system(size: 12.5)
    static let paneTitleFont = Font.system(size: 16, weight: .medium)
    static let paneHorizontalPadding: CGFloat = 28
    static let paneTopPadding: CGFloat = 20
    static let paneBottomPadding: CGFloat = 28
    static let paneSectionSpacing: CGFloat = 22
    /// Cards stop growing past this width in a wide window.
    static let paneContentMaxWidth: CGFloat = 720
    static let placeholderSize = CGSize(width: 64, height: 22)
}

/// Sidebar | hairline | selected pane, on the palette's surface.
struct SAClaudeSettingsRootView: View {
    @ObservedObject var model: SAClaudeSettingsWindowModel
    @ObservedObject var palette: SAClaudeSwiftUIPalette
    let store: SAClaudeSettingsStore
    let registry: SAClaudeSettingsViewRegistry
    weak var host: SAClaudeSettingsWindowHost?

    var body: some View {
        HStack(spacing: 0) {
            SAClaudeSettingsSidebar(model: model)
            palette.hairline
                .frame(width: 1)
                .accessibilityHidden(true)
            SAClaudeSettingsPaneView(pane: Self.pane(model.selectedPane), model: model, registry: registry, host: host)
                // A fresh view (and scroll position) per pane.
                .id(model.selectedPane)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surface)
        .environmentObject(palette)
        .environmentObject(store)
        .environment(\.claudeCommitRequests, model.commitRequests)
    }

    static func pane(_ id: SAClaudeSettingsPaneID) -> SAClaudeSettingsPane {
        // The catalog lists every pane id (its tests check the order).
        SAClaudeSettingsCatalog.panes.first { $0.id == id } ?? SAClaudeSettingsCatalog.panes[0]
    }
}

/// The nine panes, full height: icon and name, the selected one on the 8pt-radius selected fill in the primary text
/// colour, the others in the secondary colour with a hover fill.
struct SAClaudeSettingsSidebar: View {
    @ObservedObject var model: SAClaudeSettingsWindowModel

    private typealias Metrics = SAClaudeSettingsWindowMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sidebarRowSpacing) {
            ForEach(SAClaudeSettingsPaneID.allCases, id: \.self) { pane in
                SAClaudeSettingsSidebarRow(pane: pane, isSelected: model.selectedPane == pane) {
                    model.requestSelection(pane)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.sidebarPadding)
        .frame(width: Metrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }
}

struct SAClaudeSettingsSidebarRow: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let pane: SAClaudeSettingsPaneID
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private typealias Metrics = SAClaudeSettingsWindowMetrics

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: pane.symbol)
                    .font(Metrics.sidebarIconFont)
                    .frame(width: Metrics.sidebarIconWidth)
                    .accessibilityHidden(true)
                Text(NSLocalizedString(pane.titleKey, comment: ""))
                    .font(Metrics.sidebarFont)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(isSelected ? palette.text : palette.secondary)
            .padding(.horizontal, 8)
            .frame(height: Metrics.sidebarRowHeight)
            .background(RoundedRectangle(cornerRadius: Metrics.sidebarRowRadius, style: .continuous)
                .fill(isSelected ? palette.selected : (isHovered ? palette.hover : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(SAClaudeBareButtonStyle())
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One pane: its title (16pt medium) above its sections, scrolling when taller than the window; scrolls to a revealed
/// row once it is on screen.
struct SAClaudeSettingsPaneView: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let pane: SAClaudeSettingsPane
    @ObservedObject var model: SAClaudeSettingsWindowModel
    let registry: SAClaudeSettingsViewRegistry
    weak var host: SAClaudeSettingsWindowHost?

    private typealias Metrics = SAClaudeSettingsWindowMetrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Metrics.paneSectionSpacing) {
                    Text(NSLocalizedString(pane.id.titleKey, comment: ""))
                        .font(Metrics.paneTitleFont)
                        .foregroundColor(palette.text)
                        .padding(.leading, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(pane.sections, id: \.id) { section in
                        SAClaudeSettingsSectionSlot(context: SAClaudeSettingsSectionContext(
                            section: section, model: model, registry: registry, host: host))
                    }
                }
                .frame(maxWidth: Metrics.paneContentMaxWidth, alignment: .leading)
                .padding(.horizontal, Metrics.paneHorizontalPadding)
                .padding(.top, Metrics.paneTopPadding)
                .padding(.bottom, Metrics.paneBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { scrollToPendingRow(proxy, animated: false) }
            .onChange(of: model.reveal) { _ in scrollToPendingRow(proxy, animated: true) }
        }
    }

    /// A pane that has just appeared jumps to the row; one already on screen glides there.
    private func scrollToPendingRow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let rowID = model.takePendingScroll(for: pane.id) else { return }
        // Once the rows are laid out: a pane that has just appeared (or a window just shown) isn't sized on the next
        // turn yet, so it tries again a moment later (a no-op when the first one landed).
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(rowID, anchor: .center) }
            } else {
                proxy.scrollTo(rowID, anchor: .center)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { proxy.scrollTo(rowID, anchor: .center) }
            }
        }
    }
}

/// A section: its registration if it has one, else the standard heading + card.
struct SAClaudeSettingsSectionSlot: View {
    let context: SAClaudeSettingsSectionContext

    var body: some View {
        if let build = context.registry.sectionBuilder(for: context.section.id) {
            build(context)
        } else {
            context.standard
        }
    }
}

struct SAClaudeSettingsStandardSection: View {
    let context: SAClaudeSettingsSectionContext

    var body: some View {
        VStack(alignment: .leading, spacing: SAClaudeSettingsMetrics.sectionTitleGap) {
            context.heading
            SAClaudeSettingsCard {
                ForEach(Array(context.section.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SAClaudeSettingsDivider() }
                    context.row(row)
                }
            }
        }
    }
}

/// A section's small secondary heading; nothing for an untitled section.
struct SAClaudeSettingsSectionHeading: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let titleKey: String?

    var body: some View {
        if let titleKey {
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(SAClaudeSettingsMetrics.sectionTitleFont)
                .foregroundColor(palette.secondary)
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// One row: its registered body if any, else the standard row with its control; tinted while revealed; scroll id.
struct SAClaudeSettingsRowSlot: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let row: SAClaudeSettingRow
    @ObservedObject var model: SAClaudeSettingsWindowModel
    let registry: SAClaudeSettingsViewRegistry
    weak var host: SAClaudeSettingsWindowHost?

    var body: some View {
        let context = SAClaudeSettingsRowContext(row: row, infoOpen: model.openInfoRowID == row.id,
                                                 toggleInfo: { [model, id = row.id] in model.toggleInfo(id) },
                                                 model: model, registry: registry, host: host)
        let highlighted = model.highlightedRowID == row.id
        Group {
            if let build = registry.rowBuilder(for: row.id) {
                build(context)
            } else {
                context.standardRow { SAClaudeSettingsRowControl(context: context) }
            }
        }
        .background(highlighted ? palette.highlight : Color.clear)
        .animation(.easeOut(duration: 0.35), value: highlighted)
        .id(row.id)
    }
}

/// A row's control: its own registration, its standard control, its custom/dynamic registration, else the placeholder.
struct SAClaudeSettingsRowControl: View {
    let context: SAClaudeSettingsRowContext

    var body: some View {
        let row = context.row
        if context.registry.hasRowControl(row.id), let build = context.registry.registeredControl(for: row) {
            build(context)
        } else if SAClaudeSettingStandardControl.handles(row) {
            SAClaudeSettingStandardControl(row: row)
        } else if let build = context.registry.registeredControl(for: row) {
            build(context)
        } else {
            SAClaudeSettingsPlaceholderControl()
        }
    }
}

/// Stands in for a control not built yet: a quiet dashed outline, hidden from accessibility.
struct SAClaudeSettingsPlaceholderControl: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: SAClaudeSettingsWindowMetrics.placeholderSize.width,
                   height: SAClaudeSettingsWindowMetrics.placeholderSize.height)
            .accessibilityHidden(true)
    }
}

// MARK: - Pointers from elsewhere

extension SPPreferenceController {
    /// Shows Settings on the pane and row a message outside the window points to (SAClaudeSettingsPointer), opening
    /// the stale-file re-select panel only for the pointers that ask for it.
    @objc(showSettingsForPointer:)
    func showSettings(for pointer: SAClaudeSettingsPointer) {
        let target = pointer.target
        showSettingsPane(target.pane.rawValue, revealRow: target.rowID, regrantStaleFiles: target.regrantStaleFiles)
    }
}
