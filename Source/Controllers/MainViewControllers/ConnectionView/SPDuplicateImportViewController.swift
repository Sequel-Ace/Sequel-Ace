//
//  SPDuplicateImportViewController.swift
//  Sequel Ace
//
//  Simple programmatic view for handling duplicate favorites during import.
//

import Cocoa

@objc enum SPDuplicateAction: Int {
    @objc(SPDuplicateActionUpdate)
    case update = 0
    @objc(SPDuplicateActionSkip)
    case skip = 1
    @objc(SPDuplicateActionCreateNew)
    case createNew = 2
}

@objc class SPDuplicateImportItem: NSObject {
    @objc var favoriteName: String
    @objc var host: String
    @objc var action: SPDuplicateAction
    @objc var favorite: NSDictionary
    @objc var duplicateNode: SPTreeNode?

    @objc init(favoriteName: String, host: String, favorite: NSDictionary, duplicateNode: SPTreeNode?) {
        self.favoriteName = favoriteName
        self.host = host
        self.action = .update // default
        self.favorite = favorite
        self.duplicateNode = duplicateNode
        super.init()
    }
}

@objc class SPDuplicateImportHelper: NSObject {

    /// Creates an accessory view with a list of duplicates and action selectors
    @objc static func createAccessoryView(duplicateItems: [SPDuplicateImportItem]) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))

        // Create scroll view
        let scrollView = NSScrollView(frame: containerView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        // Create stack view for items
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        stackView.distribution = .fill

        // Add header
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.distribution = .fillEqually

        let nameHeader = NSTextField(labelWithString: NSLocalizedString("Connection", comment: "Connection header"))
        nameHeader.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        nameHeader.alignment = .left
        nameHeader.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let actionHeader = NSTextField(labelWithString: NSLocalizedString("Action", comment: "Action header"))
        actionHeader.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        actionHeader.alignment = .left

        headerStack.addArrangedSubview(nameHeader)
        headerStack.addArrangedSubview(actionHeader)

        NSLayoutConstraint.activate([
            nameHeader.widthAnchor.constraint(equalToConstant: 280),
            actionHeader.widthAnchor.constraint(equalToConstant: 180)
        ])

        stackView.addArrangedSubview(headerStack)

        // Add separator
        let separator = NSBox()
        separator.boxType = .separator
        stackView.addArrangedSubview(separator)

        // Add each duplicate item
        for (index, item) in duplicateItems.enumerated() {
            let itemStack = NSStackView()
            itemStack.orientation = .horizontal
            itemStack.spacing = 8
            itemStack.distribution = .fillEqually

            // Connection name label
            let nameLabel = NSTextField(labelWithString: "\(item.favoriteName) (\(item.host))")
            nameLabel.alignment = .left
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            // Action popup
            let actionPopup = NSPopUpButton()
            actionPopup.addItems(withTitles: [
                NSLocalizedString("Update", comment: "Update action"),
                NSLocalizedString("Skip", comment: "Skip action"),
                NSLocalizedString("Create New", comment: "Create new action")
            ])
            actionPopup.selectItem(at: item.action.rawValue)
            actionPopup.tag = index

            // Store reference to item for action callback
            actionPopup.target = SPDuplicateActionHandler.shared
            actionPopup.action = #selector(SPDuplicateActionHandler.actionChanged(_:))

            itemStack.addArrangedSubview(nameLabel)
            itemStack.addArrangedSubview(actionPopup)

            NSLayoutConstraint.activate([
                nameLabel.widthAnchor.constraint(equalToConstant: 280),
                actionPopup.widthAnchor.constraint(equalToConstant: 180)
            ])

            stackView.addArrangedSubview(itemStack)
        }

        // Add stack view to document view
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: CGFloat(duplicateItems.count * 30 + 60)))
        documentView.addSubview(stackView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -8)
        ])

        scrollView.documentView = documentView
        containerView.addSubview(scrollView)

        // Store items in handler
        SPDuplicateActionHandler.shared.items = duplicateItems

        return containerView
    }
}

/// Singleton to handle action changes from popup buttons
@objc class SPDuplicateActionHandler: NSObject {
    @objc static let shared = SPDuplicateActionHandler()
    @objc var items: [SPDuplicateImportItem] = []

    @objc func actionChanged(_ sender: NSPopUpButton) {
        let index = sender.tag
        guard index < items.count else { return }

        items[index].action = SPDuplicateAction(rawValue: sender.indexOfSelectedItem) ?? .update
    }
}
