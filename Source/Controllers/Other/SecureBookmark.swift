//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

final class SecureBookmark: NSObject {
    private let theData: SecureBookmarkData

    init(data: Data, options: Double, url: URL) {
        theData = SecureBookmarkData(data: data, options: options, url: url)
        super.init()
    }

    func getEncodedData() -> Data {
        if #available(OSX 10.13, *) {
            let codedData = try! NSKeyedArchiver.archivedData(withRootObject: theData, requiringSecureCoding: true)
            return codedData
        } else {
            // Fallback on earlier versions
            let codedData = NSKeyedArchiver.archivedData(withRootObject: theData)
            return codedData
        }
    }

    class func getDecodedData(encodedData: Data) -> SecureBookmarkData {
        if #available(OSX 10.13, *) {
            return try! NSKeyedUnarchiver.unarchivedObject(ofClass: SecureBookmarkData.self, from: encodedData)!
        } else {
            // Fallback on earlier versions
            return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encodedData) as! SecureBookmarkData
        }
    }
}
