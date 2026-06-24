//
//  SAHelpViewerOnlineURLBuilder.swift
//  Sequel Ace
//
//  Created by Codex on 17.06.26.
//  Copyright (c) 2026 Sequel Ace. All rights reserved.
//

import Foundation

@objc final class SAHelpViewerOnlineURLBuilder: NSObject {

    private enum MySQLDocumentID: Int {
        case mysql56 = 11
        case mysql57 = 12
        case mysql80 = 201
        case mysql84 = 371
        case mysql97 = 515
    }

    @objc(onlineHelpURLForTopic:serverVersionString:mysqlMajorVersion:mysqlMinorVersion:mysqlReleaseVersion:)
    static func onlineHelpURL(
        forTopic topic: String?,
        serverVersionString: String?,
        mysqlMajorVersion: Int,
        mysqlMinorVersion: Int,
        mysqlReleaseVersion: Int
    ) -> URL? {
        if isMariaDBServerVersion(serverVersionString) {
            return mariaDBOnlineHelpURL(forTopic: topic)
        }

        return mysqlOnlineHelpURL(
            forTopic: topic,
            documentID: mysqlDocumentID(
                major: mysqlMajorVersion,
                minor: mysqlMinorVersion,
                release: mysqlReleaseVersion
            )
        )
    }

    static func isMariaDBServerVersion(_ serverVersionString: String?) -> Bool {
        guard let serverVersionString else {
            return false
        }

        return serverVersionString.range(of: "mariadb", options: .caseInsensitive) != nil
    }

    static func mysqlDocumentID(major: Int, minor: Int, release: Int) -> Int {
        if serverVersionIsGreaterThanOrEqualTo(major: major, minor: minor, release: release, minimumMajor: 9, minimumMinor: 0, minimumRelease: 0) {
            return MySQLDocumentID.mysql97.rawValue
        }

        if serverVersionIsGreaterThanOrEqualTo(major: major, minor: minor, release: release, minimumMajor: 8, minimumMinor: 4, minimumRelease: 0) {
            return MySQLDocumentID.mysql84.rawValue
        }

        if serverVersionIsGreaterThanOrEqualTo(major: major, minor: minor, release: release, minimumMajor: 8, minimumMinor: 0, minimumRelease: 0) {
            return MySQLDocumentID.mysql80.rawValue
        }

        if serverVersionIsGreaterThanOrEqualTo(major: major, minor: minor, release: release, minimumMajor: 5, minimumMinor: 7, minimumRelease: 0) {
            return MySQLDocumentID.mysql57.rawValue
        }

        if serverVersionIsGreaterThanOrEqualTo(major: major, minor: minor, release: release, minimumMajor: 5, minimumMinor: 6, minimumRelease: 0) {
            return MySQLDocumentID.mysql56.rawValue
        }

        return MySQLDocumentID.mysql80.rawValue
    }

    static func mysqlOnlineHelpURL(forTopic topic: String?, documentID: Int) -> URL? {
        let searchString = topic ?? ""
        let urlString = "https://dev.mysql.com/doc/search/?d=\(documentID)&p=1&q=\(searchString)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

        guard let urlString, !urlString.isEmpty else {
            return nil
        }

        return URL(string: urlString)
    }

    static func mariaDBOnlineHelpURL(forTopic topic: String?) -> URL? {
        let trimmedTopic = (topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let topicSlug = trimmedTopic
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "", options: .regularExpression)

        if !topicSlug.isEmpty {
            return URL(string: "https://mariadb.com/kb/en/\(topicSlug)/")
        }

        if !trimmedTopic.isEmpty {
            var queryAllowedCharacters = CharacterSet.urlQueryAllowed
            queryAllowedCharacters.remove(charactersIn: "&=+?#")
            let encodedTopic = trimmedTopic.addingPercentEncoding(withAllowedCharacters: queryAllowedCharacters) ?? ""

            return URL(string: "https://mariadb.com/docs?q=\(encodedTopic)")
        }

        return URL(string: "https://mariadb.com/kb/en/server/")
    }

    private static func serverVersionIsGreaterThanOrEqualTo(
        major: Int,
        minor: Int,
        release: Int,
        minimumMajor: Int,
        minimumMinor: Int,
        minimumRelease: Int
    ) -> Bool {
        if major != minimumMajor {
            return major > minimumMajor
        }

        if minor != minimumMinor {
            return minor > minimumMinor
        }

        return release >= minimumRelease
    }
}
