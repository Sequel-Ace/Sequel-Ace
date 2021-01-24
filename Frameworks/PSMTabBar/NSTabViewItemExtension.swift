//
//  SPTabViewItem.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 23.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa

extension NSTabViewItem {
    @objc var databaseDocument: SPDatabaseDocument? {
        return identifier as? SPDatabaseDocument
    }
}
