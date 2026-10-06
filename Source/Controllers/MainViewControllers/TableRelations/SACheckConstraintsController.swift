import AppKit
import SwiftUI

/// Hosts the Check Constraints section inside the Relations tab.
///
/// The tab is laid out with fixed frames in DBView.xib, so the section is
/// inserted programmatically: it takes the bottom strip of the tab, and the
/// foreign key table and its buttons move up to make room. When the server has
/// no CHECK support the section is hidden and the original layout is restored.
///
/// `SPTableRelations` owns the connection and runs the queries; it supplies
/// `addHandler` and `deleteHandler`.
@objc final class SACheckConstraintsController: NSObject {

    private static let sectionHeight: CGFloat = 190
    private static let edgeMargin: CGFloat = 6
    private static let buttonGap: CGFloat = 6

    private let model = SACheckConstraintsModel()
    private var hostingView: NSHostingView<SACheckConstraintsView>?
    private weak var relationsScrollView: NSScrollView?
    private var relationsButtons: [NSView] = []

    // Vertical positions from the XIB, restored when the section is hidden.
    private var originalScrollY: CGFloat = 0
    private var originalButtonYs: [CGFloat] = []
    private var isSectionVisible = false

    /// Return a server error message on failure, nil on success.
    @objc var addHandler: ((_ name: String, _ expression: String) -> String?)? {
        get { model.addHandler }
        set { model.addHandler = newValue }
    }

    @objc var deleteHandler: ((_ names: [String]) -> Void)? {
        get { model.deleteHandler }
        set { model.deleteHandler = newValue }
    }

    /// Adds the (initially hidden) section to the view that contains the foreign
    /// key table. `buttons` are the add/delete/refresh buttons under that table.
    @objc(installBelowRelationsScrollView:relationsButtons:)
    func install(belowRelationsScrollView scrollView: NSScrollView, relationsButtons buttons: [NSView]) {
        guard hostingView == nil, let container = scrollView.superview else { return }

        relationsScrollView = scrollView
        relationsButtons = buttons
        originalScrollY = scrollView.frame.minY
        originalButtonYs = buttons.map { $0.frame.minY }

        let frame = NSRect(
            x: scrollView.frame.minX,
            y: Self.edgeMargin,
            width: scrollView.frame.width,
            height: Self.sectionHeight
        )
        let hosting = NSHostingView(rootView: SACheckConstraintsView(model: model))
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .maxYMargin]
        hosting.isHidden = true
        container.addSubview(hosting)
        hostingView = hosting
    }

    /// Refreshes the rows and shows or hides the section.
    @objc(updateWithChecks:serverSupportsChecks:takenNames:interactionEnabled:)
    func update(checks: [[String: Any]], serverSupportsChecks: Bool, takenNames: [String], interactionEnabled: Bool) {
        model.update(checks: checks, takenNames: takenNames)
        model.isEnabled = interactionEnabled
        setSectionVisible(serverSupportsChecks)
    }

    @objc(setInteractionEnabled:)
    func setInteractionEnabled(_ enabled: Bool) {
        model.isEnabled = enabled
    }

    // MARK: - Layout

    private func setSectionVisible(_ visible: Bool) {
        guard visible != isSectionVisible, let hosting = hostingView, let scrollView = relationsScrollView else { return }

        isSectionVisible = visible
        hosting.isHidden = !visible

        let top = scrollView.frame.maxY
        let scrollOffsetAboveButtons = originalScrollY - (originalButtonYs.first ?? originalScrollY)

        let buttonsY: [CGFloat]
        let scrollY: CGFloat
        if visible {
            let firstButtonY = hosting.frame.maxY + Self.buttonGap
            buttonsY = originalButtonYs.map { firstButtonY + ($0 - (originalButtonYs.first ?? $0)) }
            scrollY = firstButtonY + scrollOffsetAboveButtons
        } else {
            buttonsY = originalButtonYs
            scrollY = originalScrollY
        }

        for (button, y) in zip(relationsButtons, buttonsY) {
            button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y))
        }
        scrollView.frame = NSRect(x: scrollView.frame.minX, y: scrollY, width: scrollView.frame.width, height: max(top - scrollY, 0))
    }
}
