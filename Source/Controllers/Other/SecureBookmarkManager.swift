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

		super.init()

		// error handle?
		bookmarks = prefs.array(forKey: SPSecureBookmarks) as? [[String: Data]] ?? [["": Data()]]

		print(bookmarks.count)

//		if(bookmarks.count < 2){
//			os_log("Could not get secureBookmarks from prefs.", log: self.log, type: .error)
//			Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
//			bookmarks.removeAll()
//			return
//		}

		os_log("bookmarks = %@", log: log, type: .info, bookmarks)


		// i think part of init of this manager should be to re-request access
		reRequestSecureAccessToBookmarks()

		os_log("resolvedBookmarks = %@", log: log, type: .info, resolvedBookmarks)
		os_log("staleBookmarks = %@", log: log, type: .info, staleBookmarks)

	}


	/// reRequestSecureAccessToBookmarks
	@objc public func reRequestSecureAccessToBookmarks() {

		let bmCopy = bookmarks

        // start afresh
        bookmarks.removeAll()

		for (index, bookmarkDict) in bmCopy.enumerated(){

			os_log("Found %@ at position %i", log: log, type: .info, bookmarkDict, index)

			for (key, urlData) in bookmarkDict {

				os_log("JIMMY key = %@", log: log, type: .info, key)

				do {
					var bookmarkDataIsStale = false

                    let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                    // always resolve with just _NSURLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData , options: [_NSURLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

//                    bookmarkDataIsStale = true
//					 a bookmark might be "stale" because the app hasn't been used
//					 in many months, macOS has been upgraded, the app was
//					 re-installed, the app's preferences .plist file was deleted, etc.
					if bookmarkDataIsStale {
						os_log("The bookmark is outdated and needs to be regenerated: key = %@", log: log, type: .error, key)
                        staleBookmarks.append(URL(fileURLWithPath: key))
                    }
					else {
						os_log("Resolved bookmark: key = %@", log: log, type: .info, key)
                        let res = urlForBookmark.startAccessingSecurityScopedResource()
                        if res == true {
                            os_log("success: startAccessingSecurityScopedResource: for = %@", log: log, type: .info, key)
                            resolvedBookmarks.append(urlForBookmark)
                            bookmarks.append([urlForBookmark.absoluteString : urlData])
                        }
                        else{
                            os_log("ERROR: startAccessingSecurityScopedResource: for = %@", log: log, type: .info, key)
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

			for (index, bookmarkDict) in bookmarks.enumerated(){

				print("Found \(bookmarkDict) at position \(index)")

                if bookmarkDict[url.absoluteString] != nil {
					os_log("beenHereBefore", log: log, type: .debug)
					return true
				}
			}

			do {

				let bookmarkData = try url.bookmarkData(options: [bookmarkCreationOptions], includingResourceValuesForKeys: nil, relativeTo: nil)

                let sp = SecureBookmark(data: bookmarkData, options: Double(bookmarkCreationOptions.rawValue), url: url)

//                UserDefaults.standard.set(sp.encode(), forKey: "sp")

//                let encoder = JSONEncoder()
//                encoder.outputFormatting = .prettyPrinted
//                let data = try encoder.encode(sp)
//                print(String(data: data, encoding: .utf8)!)


                let spData = sp.getEncodedData()
				bookmarks.append([url.absoluteString : spData])
//                bookmarks.append([url.absoluteString : bookmarkData])

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
