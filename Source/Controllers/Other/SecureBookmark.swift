//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Firebase
import Foundation
import os.log

final class SecureBookmark: NSObject {
    private let bookmarkData: SecureBookmarkData

    static var emptySucureBookmarkData: SecureBookmarkData{
        return SecureBookmarkData(data: Data(), options: 0, url: URL(string: "nil")!)
    }

    init(data: Data, options: Double, url: URL) {
        bookmarkData = SecureBookmarkData(data: data, options: options, url: url)
        super.init()
    }

    func getEncodedData() -> Data? {
        if #available(OSX 10.13, *) {
            do{
                let codedData = try NSKeyedArchiver.archivedData(withRootObject: bookmarkData, requiringSecureCoding: true)
                return codedData
            }
            catch{
                os_log("Failed to encode data, Error: %@", log: OSLog.default, type: .error, error.localizedDescription)
                Crashlytics.crashlytics().log("Failed to encode data, Error: \(error.localizedDescription)")
                return nil
            }
        }
        else {
            // Fallback on earlier versions
            let codedData = NSKeyedArchiver.archivedData(withRootObject: bookmarkData)
            return codedData
        }
    }

    class func getDecodedData(encodedData: Data) -> SecureBookmarkData {
        if #available(OSX 10.13, *) {
            do{
                let retData = try NSKeyedUnarchiver.unarchivedObject(ofClass: SecureBookmarkData.self, from: encodedData) ?? emptySucureBookmarkData
                return retData
            }
            catch{
                os_log("Failed to decode data, Error: %@", log: OSLog.default, type: .error, error.localizedDescription)
                Crashlytics.crashlytics().log("Failed to decode data, Error: \(error.localizedDescription)")
                return emptySucureBookmarkData
            }
        } else {
            // Fallback on earlier versions
            do{
                let retData = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encodedData) as? SecureBookmarkData ?? emptySucureBookmarkData
                return retData
            }
            catch{
                os_log("Failed to decode data, Error: %@", log: OSLog.default, type: .error, error.localizedDescription)
                Crashlytics.crashlytics().log("Failed to encode data, Error: \(error.localizedDescription)")
                return emptySucureBookmarkData
            }
        }
    }
}

