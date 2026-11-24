import AppKit
import SwiftUI

/// Hosts the Check Constraints section inside the Relations tab.
///
/// The tab is laid out with fixed frames in DBView.xib, so the section is
/// inserted programmatically, the way the Structure tab pairs its columns and
/// indexes: the foreign key table and its buttons move into the top pane of a
/// split view, and this section is the bottom pane, with a draggable divider.
/// When the server has no CHECK support the pane is hidden and the foreign key
/// controls fill the tab as before.
///
/// `SPTableRelations` owns the connection and runs the queries; it supplies
/// `addHandler`, `deleteHandler` and `refreshHandler`.
@objc final class SACheckConstraintsController: NSObject, NSSplitViewDelegate {

    private static let defaultSectionHeight: CGFloat = 320
    private static let minimumPaneHeight: CGFloat = 120

    private let model = SACheckConstraintsModel()
    private var splitView: NSSplitView?
    private var hostingView: NSHostingView<SACheckConstraintsView>?
    private var isSectionVisible = false

    /// Last height of the section, so it comes back at the size the user left it.
    private var sectionHeight = SACheckConstraintsController.defaultSectionHeight

    /// Return a server error message on failure, nil on success.
    @objc var addHandler: ((_ name: String, _ expression: String, _ enforced: Bool) -> String?)? {
        get { model.addHandler }
        set { model.addHandler = newValue }
    }

    @objc var deleteHandler: ((_ names: [String]) -> Void)? {
        get { model.deleteHandler }
        set { model.deleteHandler = newValue }
    }

    @objc var refreshHandler: (() -> Void)? {
        get { model.refreshHandler }
        set { model.refreshHandler = newValue }
    }

    /// Moves the foreign key table and its `buttons` into a split view's top
    /// pane and adds the (initially hidden) section as the bottom pane.
    @objc(installBelowRelationsScrollView:relationsButtons:)
    func install(belowRelationsScrollView scrollView: NSScrollView, relationsButtons buttons: [NSView]) {
        guard splitView == nil, let container = scrollView.superview else { return }

        // Everything under the title label. The pane starts with the same origin
        // and size as that area, so the XIB frames of its contents stay valid.
        let region = NSRect(x: 0, y: 0, width: container.bounds.width, height: scrollView.frame.maxY)

        let relationsPane = NSView(frame: region)
        relationsPane.autoresizingMask = [.width, .height]
        for view in [scrollView] + buttons {
            relationsPane.addSubview(view)
        }

        let hosting = NSHostingView(rootView: SACheckConstraintsView(model: model))
        hosting.sizingOptions = []
        hosting.isHidden = true

        let split = NSSplitView(frame: region)
        split.isVertical = false
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        split.delegate = self
        split.addSubview(relationsPane)
        split.addSubview(hosting)

        container.addSubview(split)
        splitView = split
        hostingView = hosting
    }

    /// Refreshes the rows and shows or hides the section.
    @objc(updateWithChecks:serverSupportsChecks:supportsNotEnforced:takenNames:interactionEnabled:)
    func update(checks: [[String: Any]], serverSupportsChecks: Bool, supportsNotEnforced: Bool, takenNames: [String], interactionEnabled: Bool) {
        model.update(checks: checks, takenNames: takenNames)
        model.supportsNotEnforced = supportsNotEnforced
        model.isEnabled = interactionEnabled
        setSectionVisible(serverSupportsChecks)
    }

    @objc(setInteractionEnabled:)
    func setInteractionEnabled(_ enabled: Bool) {
        model.isEnabled = enabled
    }

    // MARK: - Layout

    private func setSectionVisible(_ visible: Bool) {
        guard visible != isSectionVisible, let split = splitView, let hosting = hostingView else { return }

        isSectionVisible = visible
        hosting.isHidden = !visible
        split.adjustSubviews()

        if visible {
            split.layoutSubtreeIfNeeded()
            split.setPosition(split.bounds.height - sectionHeight - split.dividerThickness, ofDividerAt: 0)
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, Self.minimumPaneHeight)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, max(Self.minimumPaneHeight, splitView.bounds.height - Self.minimumPaneHeight - splitView.dividerThickness))
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard isSectionVisible, let hosting = hostingView, hosting.frame.height > 0 else { return }
        sectionHeight = hosting.frame.height
    }
}
