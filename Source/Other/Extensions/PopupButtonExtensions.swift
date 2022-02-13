//
//  PopupButtonCellExtension.swift
//  Sequel Ace
//
//  Created by James on 25/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

extension NSPopUpButtonCell {

    @objc func safeAddItemWith(title: String){
        if title.isNotEmpty {
            self .addItem(withTitle: title)
        }
        else{
            print("title was nil")
        }
    }

}

extension NSPopUpButton {

    @objc func safeAddItemWith(title: String){
        if title.isNotEmpty {
            self .addItem(withTitle: title)
        }
    }
}

