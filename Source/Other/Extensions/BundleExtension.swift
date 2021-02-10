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
