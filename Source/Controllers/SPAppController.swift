//
//  SPAppController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 09.03.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import AppKit

extension SPAppController: SPWindowControllerDelegate {
    func windowControllerDidClose(_ windowController: SPWindowController) {
        windowControllers.remove(windowController)
    }
}
