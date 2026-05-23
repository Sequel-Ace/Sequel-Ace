//
//  SACellFilterAction.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

@objcMembers public final class SACellFilterAction: NSObject {
    private weak var tableContent: SPTableContent?
    public let columnName: String
    public let operatorName: String
    public let values: [String]
    public let isNull: Bool

    public init(tableContent: SPTableContent, columnName: String, operatorName: String, values: [String], isNull: Bool) {
        self.tableContent = tableContent
        self.columnName = columnName
        self.operatorName = operatorName
        self.values = values
        self.isNull = isNull
        super.init()
    }

    @objc public func apply(_ sender: Any?) {
        tableContent?.applyCellFilter(forColumn: columnName, operator: operatorName, values: values, isNull: isNull)
    }
}
