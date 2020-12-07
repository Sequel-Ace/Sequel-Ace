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
revokeBookmark
addBookmark
handle bookmarkDataIsStale

*/


@objc final class SecureBookmarkManager: NSObject {
	@objc static let sharedInstance = SecureBookmarkManager()

	@objc public var bookmarks: [Dictionary<String, Data>] = []
	private var bookmarkOptions: [Dictionary<String, UInt>] = []
	@objc public var resolvedBookmarks: [URL] = []
	@objc public var staleBookmarks: [URL] = []
	private var createdBookmarkOptions: Bool

	private let log: OSLog
	private let prefs: UserDefaults = UserDefaults.standard

	override private init() {
		log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "secureBookmarks")

		createdBookmarkOptions = prefs.bool(forKey: SPCreatedBookmarksOptions)
		super.init()

		if createdBookmarkOptions == false {
			createBookmarkOptions()
		}

		// error handle?
		bookmarks = prefs.array(forKey: SPSecureBookmarks) as? [[String: Data]] ?? [["": Data()]]
		bookmarkOptions = prefs.array(forKey: SPSecureBookmarkOptions) as? [[String: UInt]] ?? [["": 0]]

		print(bookmarks.count)

		if(bookmarks.count == 1){
			os_log("Could not get secureBookmarks from prefs.", log: self.log, type: .error)
			Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
			bookmarks.removeAll()
			return
		}

		os_log("bookmarks = %@", log: log, type: .info, bookmarks)


		// i think part of init of this manager should be to re-request access
		reRequestSecureAccessToBookmarks()

//		os_log("resolvedBookmarks = %@", log: log, type: .info, resolvedBookmarks)
//		os_log("staleBookmarks = %@", log: log, type: .info, staleBookmarks)


	}

	private func createBookmarkOptions() {

		// error handle?
		bookmarks = prefs.array(forKey: SPSecureBookmarks) as? [[String: Data]] ?? [["": Data()]]

		print(bookmarks.count)

		if(bookmarks.count == 1){
			os_log("Could not get secureBookmarks from prefs.", log: self.log, type: .error)
			Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
			bookmarks.removeAll()
			return
		}

		os_log("bookmarks = %@", log: log, type: .info, bookmarks)

		for (index, bookmarkDict) in bookmarks.enumerated(){

			os_log("Found %@ at position %i", log: log, type: .info, bookmarkDict, index)

			for (key, _) in bookmarkDict {
				let opts = URL.BookmarkResolutionOptions.withSecurityScope.rawValue // default to this as we don't know what they were created with
				bookmarkOptions.append([key : opts])
			}

		}

		os_log("createdBookmarkOptions for existing bookmarks", log: log, type: .info)
		createdBookmarkOptions = true
		prefs.set(true, forKey: SPCreatedBookmarksOptions)
		prefs.set(bookmarkOptions, forKey: SPSecureBookmarkOptions)
	}

	/// reRequestSecureAccessToBookmarks
	@objc public func reRequestSecureAccessToBookmarks() {

		//re-read ?
		bookmarkOptions = prefs.array(forKey: SPSecureBookmarkOptions) as? [[String: UInt]] ?? [["": 0]]

		let bmCopy = bookmarks

		for (index, bookmarkDict) in bmCopy.enumerated(){

			os_log("Found %@ at position %i", log: log, type: .info, bookmarkDict, index)

			for (key, urlData) in bookmarkDict {

				os_log("JIMMY key = %@", log: log, type: .info, key)

				do {

					var bookmarkOptionsForKey : UInt = 1024

					for (_, bookmarkOptionsDict) in bookmarkOptions.enumerated(){
						for (optKey, bmOptions) in bookmarkOptionsDict {

							os_log("JIMMY key = %@", log: log, type: .info, key)
							os_log("JIMMY optKey = %@", log: log, type: .info, optKey)

							if key == optKey {
								bookmarkOptionsForKey = bmOptions
								os_log("JIMMY bookmarkOptionsForKey = %i", log: log, type: .info, bookmarkOptionsForKey)
								break
							}
						}
					}

					var bookmarkDataIsStale = false

					let urlForBookmark = try URL(resolvingBookmarkData: urlData , options: [URL.BookmarkResolutionOptions(rawValue: bookmarkOptionsForKey)], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

//					 a bookmark might be "stale" because the app hasn't been used
//					 in many months, macOS has been upgraded, the app was
//					 re-installed, the app's preferences .plist file was deleted, etc.
					if bookmarkDataIsStale {
						os_log("The bookmark is outdated and needs to be regenerated: key = %@", log: log, type: .error, key)
						if regenerateBookmarkFor(url: URL(fileURLWithPath: key), options: bookmarkOptionsForKey) == true {
							os_log("Stale bookmark regenerated: key = %@", log: log, type: .error, key)
							bookmarks.remove(at: index) //
						}
						else{
							os_log("Regen failed! Stale bookmark added: key = %@", log: log, type: .error, key)
							staleBookmarks.append(URL(fileURLWithPath: key))
						}
					}
					else {
						os_log("Resolved bookmark: key = %@", log: log, type: .info, key)
						_ = urlForBookmark.startAccessingSecurityScopedResource()
						resolvedBookmarks.append(urlForBookmark)
					}

				} catch {
					staleBookmarks.append(URL(fileURLWithPath: key))
					os_log("Error resolving bookmark: key = %@. Error: %@", log: log, type: .error, key, error.localizedDescription)
					Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
				}
			}
		}

		prefs.set(bookmarks, forKey: SPSecureBookmarks)
	}

	// MAY NOT WORK - See https://stackoverflow.com/a/25247535
	/// regenerateBookmarkFor a URL.
	/// - Parameters:
	///   - url: file URL to generate secure bookmark for
	/// - Returns: Bool on success or fail
	private func regenerateBookmarkFor(url: URL, options: UInt) -> Bool {
		os_log("regenerateBookmarkFor", log: log, type: .debug)

		let bookmarkCreationOptions : URL.BookmarkCreationOptions = URL.BookmarkCreationOptions.init(rawValue: options)


		do {
			let bookmarkData = try url.bookmarkData(options: [bookmarkCreationOptions], includingResourceValuesForKeys: nil, relativeTo: nil)

//			let bookmarkData = Data()

			let tmpDict = [url.absoluteString : bookmarkData]

			// i dont think this will work ...
			let tmpURL = URL(dataRepresentation: bookmarkData, relativeTo: nil)
			_ = tmpURL?.startAccessingSecurityScopedResource()

			bookmarks.append(tmpDict)
			prefs.set(bookmarks, forKey: SPSecureBookmarks)

			return true

		} catch {
			os_log("Error regenerateBookmarkFor: key = %@. Error: %@", log: log, type: .error, url.absoluteString, error.localizedDescription)
			Crashlytics.crashlytics().log("Error regenerateBookmarkFor: key = \(url.absoluteString). Error: \(error.localizedDescription)")
			return false
		}
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

				bookmarks.append([url.absoluteString : bookmarkData])
				bookmarkOptions.append([url.absoluteString : options])
				prefs.set(bookmarks, forKey: SPSecureBookmarks)
				prefs.set(bookmarkOptions, forKey: SPSecureBookmarkOptions)

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
