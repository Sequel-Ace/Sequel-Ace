//
//  SPAutosizingTextView.swift
//  Sequel Ace
//
//  Created by Jason Morcos on 7/8/20.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Cocoa

class SPAutosizingTextView: NSTextView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
		//Ensure text view resizes to content
		if let textContainerReference = self.textContainer, let layoutManagerRef = self.layoutManager {
			layoutManagerRef.ensureLayout(for: textContainerReference)
			self.frame = layoutManagerRef.usedRect(for: textContainerReference)
			
		}
    }
    
}
