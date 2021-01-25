//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa
import SnapKit

extension SPWindowController {
    @objc func setupAppearance() {
        // Here should ahppen all UI / layout setups
    }

    @objc func setupConstraints() {
        tabBarControl.snp.makeConstraints {
            $0.top.equalToSuperview()
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(25)
        }
        tabView.snp.makeConstraints {
            $0.top.equalTo(tabBarControl.snp.bottom)
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalToSuperview()
        }
    }
}
