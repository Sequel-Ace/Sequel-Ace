//
//  SPBundleManagerAdditions.swift
//  Sequel Ace
//
//  Created by Christopher Jensen-Reimann on 10/31/21.
//  Copyright © 2021 Christopher Jensen-Reimann.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

public extension SPBundleManager {
    @objc func loadBundle(at: String) throws -> Dictionary<String, Any> {
        
        let data = try Data(contentsOf: URL(fileURLWithPath: at), options: .uncached)
        let loaded = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let pList = loaded as? Dictionary<String, Any> else {
            throw NSError(domain: "SPBundleManagerExtensions", code: 0, userInfo: nil)
        }
        return pList
    }
}

