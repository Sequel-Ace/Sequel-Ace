//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

@objcMembers final class SABundleVersionUpdater: NSObject {
    /// Returns true when a bundled default should replace an installed default bundle.
    /// Missing versions are treated as 0 to allow forward migrations.
    static func shouldUpdateDefaultBundle(installedVersion: NSNumber?, bundledVersion: NSNumber?) -> Bool {
        let installed = installedVersion?.intValue ?? 0
        let bundled = bundledVersion?.intValue ?? 0
        return bundled > installed
    }

    @objc(uniqueBundleInstallPathInDirectory:bundleName:)
    static func uniqueBundleInstallPath(in directory: String, bundleName: String) -> String {
        uniqueBundleInstallPath(in: directory, bundleName: bundleName, fileManager: .default)
    }

    static func uniqueBundleInstallPath(in directory: String, bundleName: String, fileManager: FileManager) -> String {
        let defaultPath = (directory as NSString).appendingPathComponent(bundleName)
        if !fileManager.fileExists(atPath: defaultPath) {
            return defaultPath
        }

        let baseName = (bundleName as NSString).deletingPathExtension
        let extensionName = (bundleName as NSString).pathExtension

        var candidatePath: String
        repeat {
            let suffix = UInt32.random(in: 0...UInt32.max)
            if extensionName.isEmpty {
                candidatePath = (directory as NSString).appendingPathComponent("\(baseName)_\(suffix)")
            } else {
                candidatePath = (directory as NSString).appendingPathComponent("\(baseName)_\(suffix).\(extensionName)")
            }
        } while fileManager.fileExists(atPath: candidatePath)

        return candidatePath
    }
}
