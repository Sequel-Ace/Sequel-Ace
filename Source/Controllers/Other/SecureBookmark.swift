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


//extension SecureBookmark {
//    func encode() -> Data {
//        let data = NSMutableData()
//        let archiver = NSKeyedArchiver(forWritingWith: data)
//        archiver.encode(bookmarkData, forKey: "bookmarkData")
//        archiver.encode(options, forKey: "options")
//        archiver.encode(theUrl, forKey: "theUrl")
//        archiver.finishEncoding()
//        return data as Data
//    }
//
//    init?(data: Data) {
//        let unarchiver = NSKeyedUnarchiver(forReadingWith: data)
//        defer {
//            unarchiver.finishDecoding()
//        }
//        guard let bookmarkData = unarchiver.decodeObject(forKey: "bookmarkData") as? Data else { return nil }
//        guard let theUrl = unarchiver.decodeObject(forKey: "theUrl") as? URL else { return nil }
//        options = unarchiver.decodeDouble(forKey: "options")
//        self.bookmarkData = bookmarkData
//        self.theUrl = theUrl
//    }
//}

