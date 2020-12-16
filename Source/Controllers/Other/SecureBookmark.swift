//
//  SecureBookmark.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation


class SecureBookmark: NSObject {
    var _data: SecureBookmarkData
    
    init(data: Data, options: Double, url: URL) {
        _data = SecureBookmarkData(data: data, options: options, url: url)
        super.init()
    }
    
    public func getEncodedData() -> Data{
        let codedData = NSKeyedArchiver.archivedData(withRootObject: _data)
        return codedData
    }
    
    public class func getDecodedData(encodedData: Data) -> SecureBookmarkData {
        return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encodedData) as! SecureBookmarkData
    }
}


