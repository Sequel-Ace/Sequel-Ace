//
//  AWSDirectoryBookmarkManagerTests.swift
//  Unit Tests
//
//  Unit tests for AWS directory bookmark management (sandbox support).
//

import XCTest

final class AWSDirectoryBookmarkManagerTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstanceExists() {
        let manager = AWSDirectoryBookmarkManager.shared
        XCTAssertNotNil(manager, "Shared instance should exist")
    }

    func testSharedInstanceIsSingleton() {
        let manager1 = AWSDirectoryBookmarkManager.shared
        let manager2 = AWSDirectoryBookmarkManager.shared
        XCTAssertTrue(manager1 === manager2, "Should return the same instance")
    }

    // MARK: - Path Tests

    func testAWSDirectoryPath() {
        let path = AWSDirectoryBookmarkManager.awsDirectoryPath
        XCTAssertFalse(path.isEmpty, "AWS directory path should not be empty")
        XCTAssertTrue(path.hasSuffix(".aws"), "Path should end with .aws")
        XCTAssertTrue(path.contains(NSHomeDirectory()), "Path should be in home directory")
    }

    func testAWSDirectoryPathIsConsistent() {
        let path1 = AWSDirectoryBookmarkManager.awsDirectoryPath
        let path2 = AWSDirectoryBookmarkManager.awsDirectoryPath
        XCTAssertEqual(path1, path2, "AWS directory path should be consistent")
    }

    // MARK: - Authorization State Tests

    func testIsAWSDirectoryAuthorizedReturnsBool() {
        let manager = AWSDirectoryBookmarkManager.shared
        // Just verify it returns without crashing and returns a boolean
        _ = manager.isAWSDirectoryAuthorized
        // If we get here, the property works
        XCTAssertTrue(true)
    }

    // MARK: - File Access Tests

    func testReadAWSFileContentsWithInvalidPath() {
        let manager = AWSDirectoryBookmarkManager.shared
        let contents = manager.readAWSFileContents(at: "/nonexistent/path/to/file")
        // Should return nil for non-existent file (not crash)
        XCTAssertNil(contents, "Should return nil for non-existent file")
    }

    func testAwsFileExistsWithInvalidPath() {
        let manager = AWSDirectoryBookmarkManager.shared
        let exists = manager.awsFileExists(at: "/nonexistent/path/to/file")
        XCTAssertFalse(exists, "Should return false for non-existent file")
    }

    // MARK: - Access Management Tests

    func testStartAccessingAWSDirectoryDoesNotCrash() {
        let manager = AWSDirectoryBookmarkManager.shared
        // Should not crash regardless of authorization state
        _ = manager.startAccessingAWSDirectory()
        XCTAssertTrue(true, "Should complete without crashing")
    }

    func testStopAccessingAWSDirectoryDoesNotCrash() {
        let manager = AWSDirectoryBookmarkManager.shared
        // Should not crash even if not currently accessing
        manager.stopAccessingAWSDirectory()
        XCTAssertTrue(true, "Should complete without crashing")
    }

    func testMultipleStartAccessCalls() {
        let manager = AWSDirectoryBookmarkManager.shared
        // Multiple calls should be idempotent
        let result1 = manager.startAccessingAWSDirectory()
        let result2 = manager.startAccessingAWSDirectory()
        // Both should return the same result (either both true or both false)
        XCTAssertEqual(result1, result2, "Multiple start calls should be idempotent")
    }

    func testStartAndStopAccessCycle() {
        let manager = AWSDirectoryBookmarkManager.shared
        _ = manager.startAccessingAWSDirectory()
        manager.stopAccessingAWSDirectory()
        // Should be able to start again after stopping
        _ = manager.startAccessingAWSDirectory()
        manager.stopAccessingAWSDirectory()
        XCTAssertTrue(true, "Should handle start/stop cycles without issues")
    }

    // MARK: - Notification Tests

    func testAWSDirectoryAuthorizationChangedNotificationName() {
        let notificationName = Notification.Name.AWSDirectoryAuthorizationChanged
        XCTAssertEqual(notificationName.rawValue, "AWSDirectoryAuthorizationChanged")
    }
}

final class AWSDirectoryBookmarkReplacementTests: XCTestCase {

    private var root: URL!
    private var savedBookmarkURLs: [URL] = []

    override func setUpWithError() throws {
        savedBookmarkURLs = bookmarkKeys.compactMap(URL.init(string:))

        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SequelAce-BookmarkReplace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("old/.aws"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("new/.aws"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        while AWSDirectoryBookmarkManager.shared.revokeAWSDirectoryBookmark() {}
        for url in savedBookmarkURLs where !bookmarkKeys.contains(url.absoluteString) {
            _ = SecureBookmarkManager.sharedInstance.addBookmarkFor(url: url, options: 0, isForStaleBookmark: false, isForKnownHostsFile: false)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testReplacementSwapsTheBookmark() {
        let manager = AWSDirectoryBookmarkManager.shared
        let old = root.appendingPathComponent("old/.aws", isDirectory: true)
        let new = root.appendingPathComponent("new/.aws", isDirectory: true)
        XCTAssertTrue(manager.addAWSDirectoryBookmark(from: old))

        XCTAssertTrue(manager.replaceAWSDirectoryBookmark(with: new))
        XCTAssertEqual(testBookmarkKeys, [new.absoluteString])
    }

    func testReplacementKeepsTheExistingBookmarkWhenNoNewOneCanBeCreated() {
        let manager = AWSDirectoryBookmarkManager.shared
        let old = root.appendingPathComponent("old/.aws", isDirectory: true)
        let missing = root.appendingPathComponent("missing/.aws", isDirectory: true)
        XCTAssertTrue(manager.addAWSDirectoryBookmark(from: old))

        XCTAssertFalse(manager.replaceAWSDirectoryBookmark(with: missing))
        XCTAssertEqual(testBookmarkKeys, [old.absoluteString])
    }

    private var bookmarkKeys: [String] {
        SecureBookmarkManager.sharedInstance.bookmarks.flatMap { $0.keys }
    }

    private var testBookmarkKeys: [String] {
        bookmarkKeys.filter { $0.hasPrefix(root.absoluteString) }
    }
}
