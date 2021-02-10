//
//  BundleExtension.swift
//  Sequel Ace
//
//  Created by James on 4/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation
import SwiftyJSON
import os.log

@objc extension Bundle {

	public var appName: String? {

		if let info = self.infoDictionary {
			if let appName = info[kCFBundleNameKey as String]{
				return appName as? String
			}
		}
		return nil
	}

    public var version: String? {

        if let info = self.infoDictionary {
            if let version = info["CFBundleShortVersionString"]{
                return version as? String
            }
        }

        return nil
    }

    public var bundleIdentifier: String? {

        if let info = self.infoDictionary {
            if let bundleIdentifier = info[kCFBundleIdentifierKey as String]{
                return bundleIdentifier as? String
            }
        }

        return nil
    }

    public var build: String? {

        if let info = self.infoDictionary {
            if let build = info[kCFBundleVersionKey as String]{
                return build as? String
            }
        }

        return nil
    }

    public var isSnapshotBuild: Bool {

        guard let ret = appName?.contains(SPSnapshotBuildIndicator)
        else{
            return false
        }

        return ret
    }

    public func needsUpdate() -> Bool {
        let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleIdentifier ?? "")")

        do {
            let data = try Data(contentsOf: (url ?? URL(string: ""))!) as Data
            let json = try JSON(data: data ) as JSON
            let resultCount = json["resultCount"].intValue

            if resultCount > 0 {
                let appStoreVersion = json["results"][0]["version"].stringValue
                let ret = self.version?.isVersion(lessThan: appStoreVersion)
                return ret ?? false
            }
        }
        catch{
            os_log("Error: %@", log: OSLog.default, type: .error, error.localizedDescription)
        }

        return false
    }


	/// Attempts to get the ."Sequel Ace URL scheme" from Info.plist
	/// We are looking for, see below
//	<key>CFBundleURLTypes</key>
//		<array>
//			<dict>
//				<key>CFBundleTypeRole</key>
//				<string>Editor</string>
//				<key>CFBundleURLName</key>
//				<string>Sequel Ace URL scheme</string>
//				<key>CFBundleURLSchemes</key>
//				<array>
//					<string>sequelace</string>     <--------- WE ARE LOOKING FOR THIS!
//				</array>
//			</dict>
//			<dict>
//				<key>CFBundleURLName</key>
//				<string>MySQL URL scheme</string>
//				<key>CFBundleURLSchemes</key>
//				<array>
//					<string>mysql</string>
//				</array>
//			</dict>
//		</array>
	public var saURLScheme: String? {
		guard let bundleURLTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
			return nil
		}

		let expectedDictionary = bundleURLTypes.first { $0["CFBundleURLName"] as? String == "Sequel Ace URL scheme" }
		return [(expectedDictionary?["CFBundleURLSchemes"] as? [String])?.first?.trimmedString,"://"].compactMap { $0 }.joined(separator: "")

	}
}
