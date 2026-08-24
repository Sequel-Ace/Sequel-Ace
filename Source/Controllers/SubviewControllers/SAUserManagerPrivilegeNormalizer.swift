//
//  SAUserManagerPrivilegeNormalizer.swift
//  Sequel Ace
//

import Foundation

@objc final class SAUserManagerPrivilegeNormalizer: NSObject {
    @objc(normalizedGrantName:isMariaDB:)
    static func normalizedGrantName(_ grantName: String, isMariaDB: Bool) -> String {
        guard isMariaDB,
              grantName.caseInsensitiveCompare("delete versioning rows") == .orderedSame
        else {
            return grantName
        }

        return "delete history"
    }
}
