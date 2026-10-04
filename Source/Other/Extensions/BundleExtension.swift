//
//  BundleExtension.swift
//  Sequel Ace
//
//  Created by James on 4/12/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

@objc extension Bundle {
    public var appName: String? {
        return object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
    }

    public var version: String? {
        return object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public var bundleIdentifier: String? {
        return object(forInfoDictionaryKey: kCFBundleIdentifierKey as String) as? String
    }

    public var build: String? {
        return object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
    }

    public var isSnapshotBuild: Bool {
        guard let ret = appName?.contains(SPSnapshotBuildIndicator)
        else {
            return false
        }

        return ret
    }

    public var isMASVersion: Bool {
        // App Store and TestFlight builds carry a receipt. Treat an existing
        // but unreadable receipt as App Store-originated so the GitHub updater
        // fails closed instead of offering an incompatible direct download.
        SAAppStoreReceiptPolicy.isAppStoreInstall(receiptURL: appStoreReceiptURL) { receiptURL in
            var isDirectory = ObjCBool(false)
            return FileManager.default.fileExists(
                atPath: receiptURL.path,
                isDirectory: &isDirectory
            ) && !isDirectory.boolValue
        }
    }

    public var versionString: String {
        guard
            let version: String = self.version,
            let build: String = self.build
        else {
            return ""
        }

        // e.g. "3.0.2 (3009)"
        return "%@ (%@)".format(version, build)
    }

    public var githubReleaseTag: String? {
        guard
            // Keep the key in sync with SequelAceRelease::Config::RELEASE_TAG_PLIST_KEY.
            let value = object(forInfoDictionaryKey: "SAGitHubReleaseTag") as? String,
            let version,
            let identity = SAGitHubReleaseTagIdentity(value),
            identity.version == version
        else {
            return nil
        }

        return value
    }

    public func checkForNewVersion(isFromMenuCheck: Bool) {

        if isMASVersion == false {
            let isBetaBuild = isSnapshotBuild
            GitHubReleaseManager.setup(GitHubReleaseManager.Config(user: "Sequel-Ace",
                                                                   project: "Sequel-Ace",
                                                                   includeDraft: false,
                                                                   includePrerelease: isBetaBuild,
                                                                   appVariant: isBetaBuild ? .beta : .production))

            GitHubReleaseManager.sharedInstance.checkRelease(name: versionString,
                                                             installedReleaseTag: githubReleaseTag,
                                                             isUserInitiated: isFromMenuCheck)
        }
    }

    /// Attempts to get the ."Sequel Ace URL scheme" from Info.plist
    /// We are looking for, see below
//    <key>CFBundleURLTypes</key>
//        <array>
//            <dict>
//                <key>CFBundleTypeRole</key>
//                <string>Editor</string>
//                <key>CFBundleURLName</key>
//                <string>Sequel Ace URL scheme</string>
//                <key>CFBundleURLSchemes</key>
//                <array>
//                    <string>sequelace</string>     <--------- WE ARE LOOKING FOR THIS!
//                </array>
//            </dict>
//            <dict>
//                <key>CFBundleURLName</key>
//                <string>MySQL URL scheme</string>
//                <key>CFBundleURLSchemes</key>
//                <array>
//                    <string>mysql</string>
//                </array>
//            </dict>
//        </array>
    public var saURLScheme: String? {
        guard let bundleURLTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return nil
        }

        let expectedDictionary = bundleURLTypes.first { $0["CFBundleURLName"] as? String == "Sequel Ace URL scheme" }
        return [(expectedDictionary?["CFBundleURLSchemes"] as? [String])?.first?.trimmedString, "://"].compactMap { $0 }.joined(separator: "")
    }
}
