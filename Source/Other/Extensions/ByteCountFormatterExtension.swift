//
//  ByteCountFormatterExtension.swift
//  Sequel Ace
//
//  Created by James on 3/3/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

extension ByteCountFormatter {

    @objc public static func string(byteSize: Int64) -> NSString {
        let bcf : ByteCountFormatter = ByteCountFormatter()
        bcf.zeroPadsFractionDigits = true
        bcf.countStyle = .binary

        let newString = bcf.string(fromByteCount:byteSize)

        var tmpStr = newString

        let unitMap: KeyValuePairs = ["Zero KB": "0 B","KB": "KiB", "MB": "MiB", "GB": "GiB", "bytes": "B", "TB": "TiB", "byte": "B"]

        for (fromUnits, toUnits) in unitMap {
            tmpStr = newString.replacingOccurrences(of: fromUnits, with: toUnits, options: .literal)
            if tmpStr != newString {
                break
            }
        }

        return tmpStr as NSString
    }
}
