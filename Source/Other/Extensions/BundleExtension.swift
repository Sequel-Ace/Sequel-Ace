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

    public func updateAvailable() -> Dictionary<String, String> {
        let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleIdentifier ?? "")")
        var responseDict: [String : String] = ["updateAvailable" : String(false)]
        do {
            let data = try Data(contentsOf: (url ?? URL(string: ""))!) as Data
            let json = try JSON(data: data ) as JSON
            let resultCount = json["resultCount"].intValue

            if resultCount > 0 {
                let appStoreVersion = json["results"][0]["version"].stringValue

                let ret = self.version?.isVersion(lessThan: appStoreVersion)
                if ret == true {
                    let currentVersionReleaseDate = json["results"][0]["currentVersionReleaseDate"].stringValue
                    os_log("currentVersionReleaseDate: %@", log: OSLog.default, type: .debug, currentVersionReleaseDate)

                    // e.g format from JSON 2021-01-20T22:25:56Z
                    // convert to a date
                    let date = currentVersionReleaseDate.iso8601DateStringToDate()

                    os_log("currentVersionReleaseDate: %@", log: OSLog.default, type: .debug, date as CVarArg)

                    // create a date = currentVersionReleaseDate + 2 days
                    let leadTime = date.addDaysToDate(daysToAdd: 2)

                    os_log("leadTime: %@", log: OSLog.default, type: .debug, leadTime as CVarArg)

                    if (leadTime.timeIntervalSinceNow.sign == .minus) {
                        // date is in the past. i.e. more than X days have passed since the release
                        os_log("leadTime is in the past: %@", log: OSLog.default, type: .debug, leadTime as CVarArg)
                        var releaseNotes = json["results"][0]["releaseNotes"].stringValue

                        releaseNotes = releaseNotes.summarize(toLength: 280, withEllipsis: true)!

                        os_log("releaseNotes: %@", log: OSLog.default, type: .debug, releaseNotes)

                        responseDict["updateAvailable"] = String(true)
                        responseDict["currentVersion"] = self.version
                        responseDict["appStoreVersion"] = appStoreVersion
                        responseDict["releaseNotes"] = releaseNotes
                    }
                }

                return responseDict
            }
        }
        catch{
            os_log("Error: %@", log: OSLog.default, type: .error, error.localizedDescription)
        }

        return responseDict
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
