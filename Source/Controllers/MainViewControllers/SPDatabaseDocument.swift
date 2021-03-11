//
//  SPDatabaseDocument.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 11.03.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import AppKit

extension SPDatabaseDocument {
    @objc var swiftTabAccessoryView: NSView {
        let view = NSView()
        view.wantsLayer = true
        view.snp.makeConstraints {
            $0.size.equalTo(16)
        }
        view.layer?.cornerRadius = 8
        return view
    }
}
