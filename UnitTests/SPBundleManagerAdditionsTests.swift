//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SPBundleManagerAdditionsTests: XCTestCase {

    func testShouldUpdateDefaultBundleWhenBundledVersionIsHigher() {
        XCTAssertTrue(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 2),
                bundledVersion: NSNumber(value: 3)
            )
        )
    }

    func testShouldNotUpdateDefaultBundleWhenVersionsAreEqual() {
        XCTAssertFalse(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 3),
                bundledVersion: NSNumber(value: 3)
            )
        )
    }

    func testShouldNotUpdateDefaultBundleWhenInstalledVersionIsHigher() {
        XCTAssertFalse(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 4),
                bundledVersion: NSNumber(value: 3)
            )
        )
    }

    func testShouldUpdateDefaultBundleWhenInstalledVersionIsMissing() {
        XCTAssertTrue(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: nil,
                bundledVersion: NSNumber(value: 1)
            )
        )
    }

    func testShouldNotUpdateDefaultBundleWhenBundledVersionIsMissing() {
        XCTAssertFalse(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 3),
                bundledVersion: nil
            )
        )
    }

    func testUniqueBundleInstallPathReturnsDefaultPathWhenNotTaken() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempDir) }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundleName = "CopyasMarkdown.saBundle"
        let expectedPath = tempDir.appendingPathComponent(bundleName).path
        let uniquePath = SABundleVersionUpdater.uniqueBundleInstallPath(in: tempDir.path, bundleName: bundleName)

        XCTAssertEqual(uniquePath, expectedPath)
    }

    func testUniqueBundleInstallPathKeepsExtensionWhenDefaultPathExists() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempDir) }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let bundleName = "CopyasMarkdown.saBundle"
        let existingPath = tempDir.appendingPathComponent(bundleName)
        try fileManager.createDirectory(at: existingPath, withIntermediateDirectories: true)

        let uniquePath = SABundleVersionUpdater.uniqueBundleInstallPath(in: tempDir.path, bundleName: bundleName)
        let uniqueName = (uniquePath as NSString).lastPathComponent

        XCTAssertNotEqual(uniquePath, existingPath.path)
        XCTAssertTrue(uniqueName.hasPrefix("CopyasMarkdown_"))
        XCTAssertEqual((uniqueName as NSString).pathExtension, "saBundle")
        XCTAssertFalse(fileManager.fileExists(atPath: uniquePath))
    }
}
