//
//  NSViewExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa

extension NSView {
    func addSubviews(_ subviews: [NSView]) {
        subviews.forEach { self.addSubview($0) }
    }

    func addSubviews(_ subviews: NSView...) {
        subviews.forEach { self.addSubview($0) }
    }
}
