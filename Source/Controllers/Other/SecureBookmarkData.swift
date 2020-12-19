//
//  SecureBookmarkData.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

final class SecureBookmarkData: NSObject {
 
    internal let bookmarkData: Data
    internal let options: Double
    internal let theUrl: URL

    init(data: Data, options: Double, url: URL ) {
        self.bookmarkData = data
        self.options = options
        self.theUrl = url
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
        case theUrl = "TheUrl"
    }

    func encode(with coder: NSCoder) {

        if #available(OSX 10.13, *) {
            //For NSSecureCoding
            coder.encode(bookmarkData as NSData, forKey: Keys.bookmarkData.rawValue)
            coder.encode(NSNumber(value: options), forKey: Keys.options.rawValue)
            coder.encode(theUrl as NSURL, forKey: Keys.theUrl.rawValue)
        }
        else {
            // For NSCoding
            coder.encode(bookmarkData, forKey: Keys.bookmarkData.rawValue)
            coder.encode(options, forKey: Keys.options.rawValue)
            coder.encode(theUrl, forKey: Keys.theUrl.rawValue)
        }
    }

    convenience init?(coder: NSCoder) {

        if #available(OSX 10.13, *) {
            let bookmarkData = coder.decodeObject(of: NSData.self, forKey: Keys.bookmarkData.rawValue)! as Data
            let options = coder.decodeObject(of: NSNumber.self, forKey: Keys.options.rawValue)! as! Double
            let theUrl = coder.decodeObject(of: NSURL.self, forKey: Keys.theUrl.rawValue)! as URL
            self.init(data: bookmarkData, options: options, url: theUrl)
        }
        else{
            // For NSCoding
            let bookmarkData = coder.decodeObject(forKey: Keys.bookmarkData.rawValue) as! Data
            let options = coder.decodeDouble(forKey: Keys.options.rawValue)
            let theUrl = coder.decodeObject(forKey: Keys.theUrl.rawValue) as! URL
            self.init(data: bookmarkData, options: options, url: theUrl)
        }
    }
}

