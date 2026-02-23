//
//  SecureBookmarkManagerStub.swift
//  Unit Tests
//
//  Lightweight test double for SecureBookmarkManager used by AWS unit tests.
//

import Foundation

@objc(SecureBookmarkManager)
@objcMembers final class SecureBookmarkManagerStub: NSObject {

    static let sharedInstance = SecureBookmarkManagerStub()

    // Mirrors the API consumed by AWSDirectoryBookmarkManager.
    var bookmarks: [[String: Data]] = []

    private var resolvedURLs = [String: URL]()

    func bookmarkFor(filename: String) -> URL? {
        return resolvedURLs[filename]
    }

    func addBookmarkFor(
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

    func revokeBookmark(filename: String) -> Bool {
        bookmarks.removeAll { $0.keys.contains(filename) }
        resolvedURLs.removeValue(forKey: filename)
        return true
    }
}

// Keep the production class name available to Swift call sites in tests.
typealias SecureBookmarkManager = SecureBookmarkManagerStub
