//
//  SecureBookmarkManager.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation
import os.log
import Firebase


/*
reRequestSecureAccess
addBookmark
handle bookmarkDataIsStale

*/

@objc final class SecureBookmarkManager: NSObject {
	@objc static let sharedInstance = SecureBookmarkManager()
	@objc public var bookmarks: [Dictionary<String, Data>] = []
	@objc public var resolvedBookmarks: [URL] = []
	@objc public var staleBookmarks: [URL] = []
    private let _NSURLBookmarkResolutionWithSecurityScope = URL.BookmarkResolutionOptions(rawValue: 1 << 10)

	private let log: OSLog
	private let prefs: UserDefaults = UserDefaults.standard

	override private init() {
		log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "secureBookmarks")

        os_log("SecureBookmarkManager init = %@", log: log, type: .info)
        Crashlytics.crashlytics().log("SecureBookmarkManager init.")

		super.init()

		bookmarks = prefs.array(forKey: SPSecureBookmarks) as? [[String: Data]] ?? [["": Data()]]

        // the default above means there is always one entry, even if there are none in prefs
        // so check for less than 2
		if(bookmarks.count < 2){
			os_log("Could not get secureBookmarks from prefs.", log: self.log, type: .error)
			Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
			bookmarks.removeAll()
			return
		}

		os_log("bookmarks = %@", log: log, type: .info, bookmarks)

		// I think part of init of this manager should be to re-request access
		reRequestSecureAccessToBookmarks()

        os_log("resolvedBookmarks count = %i", log: log, type: .info, resolvedBookmarks.count)
        os_log("staleBookmarks count = %i", log: log, type: .info, staleBookmarks.count)

        Crashlytics.crashlytics().log("resolvedBookmarks count = \(resolvedBookmarks.count)")
        Crashlytics.crashlytics().log("staleBookmarks count = \(staleBookmarks.count)")
	}


	/// reRequestSecureAccessToBookmarks
    // loops through current bookmarks from prefs and re-requests secure access
    // NOTE: when re-requesting access (resolvingBookmarkData) you only need to use
    // _NSURLBookmarkResolutionWithSecurityScope, not the options it was originally created with
    // otherwise it will be markes as stale.
	@objc public func reRequestSecureAccessToBookmarks() {

		let bmCopy = bookmarks

        // start afresh
        bookmarks.removeAll()

        for (_, bookmarkDict) in bmCopy.enumerated(){
			for (key, urlData) in bookmarkDict {

				os_log("Bookmark URL = %@", log: log, type: .info, key)

				do {
					var bookmarkDataIsStale = false

                    os_log("Attempting to getDecodedData for %@", log: log, type: .debug, key)
                    Crashlytics.crashlytics().log("Attempting to getDecodedData for: \(key)")
                    let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                    os_log("Attempting to resolve bookmark data for %@", log: log, type: .debug, spData.debugDescription)
                    Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(spData.debugDescription)")
                    // always resolve with just _NSURLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData , options: [_NSURLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

//                    bookmarkDataIsStale = true
//					 a bookmark might be "stale" because the app hasn't been used
//					 in many months, macOS has been upgraded, the app was
//					 re-installed, the app's preferences .plist file was deleted, etc.
					if bookmarkDataIsStale {
						os_log("The bookmark is outdated and needs to be regenerated: key = %@", log: log, type: .error, key)
                        Crashlytics.crashlytics().log("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        staleBookmarks.append(URL(fileURLWithPath: key))
                    }
					else {
						os_log("Resolved bookmark: %@", log: log, type: .info, key)
                        Crashlytics.crashlytics().log("Resolved bookmark: \(key)")
                        let res = urlForBookmark.startAccessingSecurityScopedResource()
                        if res == true {
                            os_log("success: startAccessingSecurityScopedResource for: %@", log: log, type: .info, key)
                            Crashlytics.crashlytics().log("success: startAccessingSecurityScopedResource for: \(key)")
                            resolvedBookmarks.append(urlForBookmark)
                            bookmarks.append([urlForBookmark.absoluteString : urlData])
                        }
                        else{
                            os_log("ERROR: startAccessingSecurityScopedResource for: %@", log: log, type: .info, key)
                            Crashlytics.crashlytics().log("ERROR: startAccessingSecurityScopedResource for: \(key)")
                            staleBookmarks.append(URL(fileURLWithPath: key))
                        }
					}
				} catch {
					staleBookmarks.append(URL(fileURLWithPath: key))
					os_log("Error resolving bookmark: key = %@. Error: %@", log: log, type: .error, key, error.localizedDescription)
					Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
				}
			}
		}

        // reset bookmarks
		prefs.set(bookmarks, forKey: SPSecureBookmarks)

	}


	/// addBookMark
	///  - Parameters:
	///	 - url: file URL to generate secure bookmark for
	///	 - options: URL.BookmarkCreationOptions. see https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions
	/// - Returns: Bool on success or fail
	@objc public func addBookMarkFor(url: URL, options: UInt) -> Bool {

		let bookmarkCreationOptions : URL.BookmarkCreationOptions = URL.BookmarkCreationOptions.init(rawValue: options)

		if url.startAccessingSecurityScopedResource() {
            os_log("success: startAccessingSecurityScopedResource for: %@", log: log, type: .info, url.absoluteString)
            Crashlytics.crashlytics().log("success: startAccessingSecurityScopedResource for: \(url.absoluteString)")

            for (_, bookmarkDict) in bookmarks.enumerated(){
                if bookmarkDict[url.absoluteString] != nil {
                    os_log("Existing bookmark for:", log: log, type: .debug, url.absoluteString)
                    Crashlytics.crashlytics().log("Existing bookmark for: \(url.absoluteString)")
					return true
				}
			}

			do {
                // any errors are caught below in the catch{}
                os_log("Attempting to create secure bookmark for %@ - with bookmarkCreationOptions: %i", log: log, type: .debug, url.absoluteString, bookmarkCreationOptions.rawValue)
                Crashlytics.crashlytics().log("Attempting to create secure bookmark for: \(url.absoluteString) - with bookmarkCreationOptions:\(bookmarkCreationOptions.rawValue)")
				let bookmarkData = try url.bookmarkData(options: [bookmarkCreationOptions], includingResourceValuesForKeys: nil, relativeTo: nil)

                os_log("Attempting to create SecureBookmark object for %@", log: log, type: .debug, url.absoluteString)
                Crashlytics.crashlytics().log("Attempting to create SecureBookmark object for: \(url.absoluteString)")
                let sp = SecureBookmark(data: bookmarkData, options: Double(bookmarkCreationOptions.rawValue), url: url)

                os_log("Attempting to getEncodedData for %@", log: log, type: .debug, sp.debugDescription)
                Crashlytics.crashlytics().log("Attempting getEncodedData for: \(sp.debugDescription)")
                let spData = sp.getEncodedData()

                os_log("Adding %@ to bookmarks", log: log, type: .debug, url.absoluteString)
                Crashlytics.crashlytics().log("Adding \(url.absoluteString) to bookmarks")
				bookmarks.append([url.absoluteString : spData])

                os_log("Updating UserDefaults", log: log, type: .debug)
                Crashlytics.crashlytics().log("Updating UserDefaults")
				prefs.set(bookmarks, forKey: SPSecureBookmarks)

				return true

			} catch {
				os_log("Error creating secure Bookmark For: key = %@. Error: %@", log: log, type: .error, url.absoluteString, error.localizedDescription)
				Crashlytics.crashlytics().log("Error creating secure Bookmark For: key = \(url.absoluteString). Error: \(error.localizedDescription)")
				return false
			}
		}
		else{
			os_log("Error startAccessingSecurityScopedResource For: key = %@.", log: log, type: .error, url.absoluteString)
			Crashlytics.crashlytics().log("Error startAccessingSecurityScopedResource For: key = \(url.absoluteString).")
			return false
		}
	}
}
