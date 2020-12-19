//
//  SecureBookmarkData.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

final class SecureBookmarkData: NSObject {
    let bookmarkData: Data
    private let options: Double
    private let bookmarkURL: URL

    init(data: Data, options: Double, url: URL) {
        bookmarkData = data
        self.options = options
        bookmarkURL = url
        super.init()
    }
}

extension SecureBookmarkData: NSCoding, NSSecureCoding {
    static var supportsSecureCoding: Bool {
        return true
    }

    // MARK: NSCoding Implementation

    enum Keys: String {
        case bookmarkData = "BookmarkData"
        case options = "Options"
        case bookmarkURL = "BookmarkURL"
    }

    func encode(with coder: NSCoder) {
        if #available(OSX 10.13, *) {
            // For NSSecureCoding
            coder.encode(bookmarkData as NSData, forKey: Keys.bookmarkData.rawValue)
            coder.encode(NSNumber(value: options), forKey: Keys.options.rawValue)
            coder.encode(bookmarkURL as NSURL, forKey: Keys.bookmarkURL.rawValue)
        } else {
            // For NSCoding
            coder.encode(bookmarkData, forKey: Keys.bookmarkData.rawValue)
            coder.encode(options, forKey: Keys.options.rawValue)
            coder.encode(bookmarkURL, forKey: Keys.bookmarkURL.rawValue)
        }
    }

    convenience init?(coder: NSCoder) {
        if #available(OSX 10.13, *) {
            let bookmarkData = coder.decodeObject(of: NSData.self, forKey: Keys.bookmarkData.rawValue)! as Data
            let options = coder.decodeObject(of: NSNumber.self, forKey: Keys.options.rawValue)! as! Double
            let bookmarkURL = coder.decodeObject(of: NSURL.self, forKey: Keys.bookmarkURL.rawValue)! as URL
            self.init(data: bookmarkData, options: options, url: bookmarkURL)
        } else {
            // For NSCoding
            let bookmarkData = coder.decodeObject(forKey: Keys.bookmarkData.rawValue) as! Data
            let options = coder.decodeDouble(forKey: Keys.options.rawValue)
            let bookmarkURL = coder.decodeObject(forKey: Keys.bookmarkURL.rawValue) as! URL
            self.init(data: bookmarkData, options: options, url: bookmarkURL)
        }
    }
}
