//
//  NSImageExtensions.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 23.12.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Cocoa

extension NSImage {
    @objc func image(overlayColor: NSColor) -> NSImage {
        if self.isTemplate == false {
            return self
        }
        guard let image = self.copy() as? NSImage else {
            return self
        }
        image.lockFocus()
        overlayColor.set()
        
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceIn)
        
        image.unlockFocus()
        image.isTemplate = false
        
        return image
    }
}
