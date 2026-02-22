//
//  SecureBookmarkManagerStub.swift
//  Unit Tests
//
//  Lightweight test double for SecureBookmarkManager used by AWS unit tests.
//

import Foundation

@objc final class SecureBookmarkManager: NSObject {

    @objc static let sharedInstance = SecureBookmarkManager()

    // Mirrors the API consumed by AWSDirectoryBookmarkManager.
    @objc var bookmarks: [[String: Data]] = []

    private var resolvedURLs = [String: URL]()

    @objc func bookmarkFor(filename: String) -> URL? {
        return resolvedURLs[filename]
    }

    @objc func addBookmarkFor(
        url: URL,
        options: UInt,
        isForStaleBookmark: Bool,
        isForKnownHostsFile: Bool
    ) -> Bool {
        let key = url.absoluteString
        if !bookmarks.contains(where: { $0.keys.contains(key) }) {
            bookmarks.append([key: Data()])
        }
        resolvedURLs[key] = url
        return true
    }

    @objc func revokeBookmark(filename: String) -> Bool {
        bookmarks.removeAll { $0.keys.contains(filename) }
        resolvedURLs.removeValue(forKey: filename)
        return true
    }
}
