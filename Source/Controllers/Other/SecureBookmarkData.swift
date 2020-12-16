//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

class SecureBookmarkData: NSObject, NSCoding, NSSecureCoding {
 
    var bookmarkData: Data
    var options: Double
    var theUrl: URL
    
    static var supportsSecureCoding: Bool {
        return true
    }
   
    init(data: Data, options: Double, url: URL ) {
        self.bookmarkData = data
        self.options = options
        self.theUrl = url
        super.init()
    }
    
    // MARK: NSCoding Implementation
    enum Keys: String {
        case bookmarkData = "BookmarkData"
        case options = "Options"
        case theUrl = "TheUrl"
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(bookmarkData, forKey: Keys.bookmarkData.rawValue)
        coder.encode(options, forKey: Keys.options.rawValue)
        coder.encode(theUrl, forKey: Keys.theUrl.rawValue)
        
        //    For NSSecureCoding
        //    coder.encode(bookmarkData as NSData, forKey: Keys.bookmarkData.rawValue)
        //    coder.encode(NSNumber(value: options), forKey: Keys.options.rawValue)
        //    coder.encode(theUrl as NSURL, forKey: Keys.theUrl.rawValue)

    }
    
    required convenience init?(coder: NSCoder) {
        let bookmarkData = coder.decodeObject(forKey: Keys.bookmarkData.rawValue) as! Data
        let options = coder.decodeDouble(forKey: Keys.options.rawValue)
        let theUrl = coder.decodeObject(forKey: Keys.theUrl.rawValue) as! URL
        self.init(data: bookmarkData, options: options, url: theUrl)
    }
    
    
}



