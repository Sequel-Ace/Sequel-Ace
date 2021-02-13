//
//  BundleExtension.swift
//  Sequel Ace
//
//  Created by James on 4/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

@objc extension Bundle {

    public var appName: String? {
        return self.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
    }

    public var version: String? {
        return self.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public var bundleIdentifier: String? {
        return self.object(forInfoDictionaryKey: kCFBundleIdentifierKey as String) as? String
    }

    public var build: String? {
        return self.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
    }

    public var isSnapshotBuild: Bool {

        guard let ret = appName?.contains(SPSnapshotBuildIndicator)
        else{
            return false
        }

        return ret
    }

    public var isMASVersion: Bool {

        guard
            let receiptURL : URL = self.appStoreReceiptURL
        else{
            return false
        }

        do {
            let _ : Data = try Data(contentsOf: receiptURL)
            return true
        }
        catch {
            return false
        }
    }

    public var versionString: String {
        guard
            let version : String = self.version,
            let build   : String = self.build
        else{
            return ""
        }

        // e.g. "3.0.2 (3009)"
        return "%@ (%@)" .format(version, build)
    }

    public func checkForNewVersion(){

        if isMASVersion == false {
            GitHubReleaseManager.setup(GitHubReleaseManager.Config(user: "Sequel-Ace", project: "Sequel-Ace", includeDraft: false, includePrerelease: true))
            GitHubReleaseManager.sharedInstance.checkReleaseWithName(name: versionString)
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
        return [(expectedDictionary?["CFBundleURLSchemes"] as? [String])?.first?.trimmedString,"://"].compactMap { $0 }.joined(separator: "")

    }
}
