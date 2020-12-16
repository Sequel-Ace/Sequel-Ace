//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation


struct SecureBookmark: Codable {
	let bookmarkData: Data
    let options: Double
    let theUrl: URL
}


extension SecureBookmark {
    func encode() -> Data {
        let data = NSMutableData()
        let archiver = NSKeyedArchiver(forWritingWith: data)
        archiver.encode(NSKeyedArchiver.archivedData(withRootObject: bookmarkData), forKey: "bookmarkData")
        archiver.encode(NSKeyedArchiver.archivedData(withRootObject: options), forKey: "options")
        archiver.encode(NSKeyedArchiver.archivedData(withRootObject: theUrl), forKey: "theUrl")
        archiver.finishEncoding()
        return data as Data
    }

    init?(data: Data) {
        let unarchiver = NSKeyedUnarchiver(forReadingWith: data)
        defer {
            unarchiver.finishDecoding()
        }
        guard
            let bookmarkData = unarchiver.decodeObject(forKey: "bookmarkData") as? Data,
            let unarchivedBookmarkData = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(bookmarkData) as? Data
        
        else {
            return nil
        }
        guard
            let theUrl = unarchiver.decodeObject(forKey: "theUrl") as? Data,
            let unarchivedURL = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(theUrl) as? URL
        
        else {
            return nil
        }
        guard
            let options = unarchiver.decodeObject(forKey: "options") as? Data,
            let unarchivedOptions = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(options) as? Double
        
        else {
            return nil
        }
        
        self.bookmarkData = unarchivedBookmarkData
        self.theUrl = unarchivedURL
        self.options = unarchivedOptions
    }
}

