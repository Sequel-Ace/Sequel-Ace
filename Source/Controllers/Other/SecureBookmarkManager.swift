//
//  SecureBookmarkManager.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Firebase
import Foundation
import OSLog

/*
 reRequestSecureAccess
 addBookmark
 handle bookmarkDataIsStale
 revokeBookmark
 stopAllSecurityScopedAccess

 */

@objc final class SecureBookmarkManager: NSObject {
    @objc static let sharedInstance = SecureBookmarkManager()

    @objc var bookmarks: [Dictionary<String, Data>] = []
    @objc var staleBookmarks: [String] = []

    private var resolvedBookmarks: [URL] = []
    private let URLBookmarkResolutionWithSecurityScope = URL.BookmarkResolutionOptions(rawValue: 1 << 10)
    private let URLBookmarkCreationWithSecurityScope = URL.BookmarkCreationOptions(rawValue: 1 << 11)

    private let prefs: UserDefaults = UserDefaults.standard
    private var observer: NSKeyValueObservation?

    private var iChangedTheBookmarks: Bool = false
    private var bookmarksHaveBeenMigrated: Bool = false
    private let Log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "secureBookmarks")


    override init() {

        Log.info("SecureBookmarkManager init.")
        Log.info("OSLog.Options.defaultPrivacy: \(OSLog.Options.defaultPrivacy)")
        Log.info("OSLog.Options.logFileName: \(OSLog.Options.logFileName)")
        
        Crashlytics.crashlytics().log("SecureBookmarkManager init.")

        super.init()

        // this manager *should* be the only thing changing the bookmarks pref, but in case...
        observer = UserDefaults.standard.observe(\.SPSecureBookmarks, options: [.new, .old], changeHandler: { [self] _, change in

            if iChangedTheBookmarks == false {
                Log.debug("SPSecureBookmarks changed, but NOT by SecureBookmarkManager.")
                Crashlytics.crashlytics().log("SPSecureBookmarks changed, but NOT by SecureBookmarkManager.")
                bookmarks.removeAll()
                bookmarks = change.newValue!
            }
            // reset
            iChangedTheBookmarks = false

            // post notificay for ConnectionController
            NotificationCenter.default.post(name: Notification.Name(NSNotification.Name.SPBookmarksChanged.rawValue), object: self)

        })

        guard let secureBookmarks = prefs.array(forKey: SASecureBookmarks) as? [[String: Data]], secureBookmarks.isNotEmpty else {
            Log.error("Could not get secureBookmarks from prefs.")
            Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
            return
        }

        staleBookmarks = prefs.array(forKey: SPStaleSecureBookmarks) as? [String] ?? []

        bookmarks = secureBookmarks

        Log.info("bookmarks = \(bookmarks)")

        let bookmarksHaveBeenMigrated = prefs.bool(forKey: SPSecureBookmarksHaveBeenMigrated)
        Log.debug("bookmarksHaveBeenMigrated = \(bookmarksHaveBeenMigrated)")

        if bookmarksHaveBeenMigrated == false {
            if migrateBookmarks() == true {
                // after migration, re-request.
                reRequestSecureAccessToBookmarks()
            }
        }
        else {
            // I think part of init of this manager should be to re-request access
            reRequestSecureAccessToBookmarks()
        }

        Log.info("resolvedBookmarks count = \(resolvedBookmarks.count)")
        Log.info("staleBookmarks count = \(staleBookmarks.count)")

        Crashlytics.crashlytics().log("resolvedBookmarks count = \(resolvedBookmarks.count)")
        Crashlytics.crashlytics().log("staleBookmarks count = \(staleBookmarks.count)")
    }

    /// migrateBookmarks
    // load up old bookmarks into array
    // loop though resolving them to URLS
    // Attempt to create secure bookmark
    // Attempt to create SecureBookmark object
    // Attempt to getEncodedData for object
    // Add to bookmarks and save to prefs
    private func migrateBookmarks() -> Bool {
        Log.debug("migrating old format Bookmarks.")

        var migratedBookmarks: [Dictionary<String, Data>] = []

        for bookmarkDict in bookmarks {
            for (key, urlData) in bookmarkDict {
                Log.info("Bookmark URL = \(key)")

                var bookmarkDataIsStale = false

                do {
                    Log.debug("Attempting to resolve bookmark data for \(key)")
                    Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                    // always resolve with just URLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: urlData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                    if bookmarkDataIsStale {
                        Log.error("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        Crashlytics.crashlytics().log("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        staleBookmarks.appendIfNotContains(key)
                        continue
                    } else {
                        Log.info("Resolved bookmark: \(key)")
                        Crashlytics.crashlytics().log("Resolved bookmark: \(key)")
                    }

                    Log.debug("Attempting to create SecureBookmark object for: \(urlForBookmark.absoluteString)")
                    Crashlytics.crashlytics().log("Attempting to create SecureBookmark object for: \(urlForBookmark.absoluteString)")
                    // NSURLBookmarkCreationWithSecurityScope is a guess .. could be read only, BUT read only fails to resolve! so it has to be securityScope
                    let sp = SecureBookmark(data: urlData, options: Double(URLBookmarkCreationWithSecurityScope.rawValue), url: urlForBookmark)

                    Log.debug("Attempting getEncodedData for: \(sp.debugDescription)")
                    Crashlytics.crashlytics().log("Attempting getEncodedData for: \(sp.debugDescription)")

                    guard let spData = sp.getEncodedData() else {
                        Crashlytics.crashlytics().log("Failed to getEncodedData for: \(sp.debugDescription)")
                        Log.error("Failed to getEncodedData for: \(sp.debugDescription)")
                        staleBookmarks.appendIfNotContains(key)
                        continue
                    }

                    Crashlytics.crashlytics().log("SUCCESS: Migrated: \(urlForBookmark.absoluteString)")
                    Log.debug("SUCCESS: Migrated: \(urlForBookmark.absoluteString)")
                    migratedBookmarks.append([urlForBookmark.absoluteString: spData])

                }
                catch {
                    staleBookmarks.appendIfNotContains(key)
                    Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                    Log.error("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                    continue
                }
            }
        }

        bookmarksHaveBeenMigrated = true
        iChangedTheBookmarks = true

        // update prefs - keep a copy of the old bookmark data for the moment
        prefs.set(true, forKey: SPSecureBookmarksHaveBeenMigrated)
        prefs.set(migratedBookmarks, forKey: SASecureBookmarks)
        prefs.set(bookmarks, forKey: SPSecureBookmarksOldFormat) // backup
        prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)

        return true
    }

    /// reRequestSecureAccessToBookmarks
    // loops through current bookmarks from prefs and re-requests secure access
    // NOTE: when re-requesting access (resolvingBookmarkData) you only need to use
    // URLBookmarkResolutionWithSecurityScope, not the options it was originally created with
    // otherwise it will be markes as stale.
    private func reRequestSecureAccessToBookmarks() {

        // re-read - must do this after migration, could put it in an if, but it only happens once per app start.
        guard let secureBookmarks = prefs.array(forKey: SASecureBookmarks) as? [[String: Data]], secureBookmarks.isNotEmpty else {
            Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
            Log.error("Could not get secureBookmarks from prefs.")
            return
        }

        bookmarks = secureBookmarks

        let bmCopy = bookmarks

        // start afresh
        bookmarks.removeAll()

        for bookmarkDict in bmCopy {
            for (key, urlData) in bookmarkDict {
                Log.info("Bookmark URL = \(key)")

                do {
                    var bookmarkDataIsStale = false

                    Crashlytics.crashlytics().log("Attempting to getDecodedData for: \(key)")
                    Log.debug("Attempting to getDecodedData for: \(key)")
                    let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                    Log.debug("Attempting to resolve bookmark data for: \(key)")
                    Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                    // always resolve with just URLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                    //a bookmark might be "stale" because the app hasn't been used
                    //in many months, macOS has been upgraded, the app was
                    //re-installed, the app's preferences .plist file was deleted, etc.
                    if bookmarkDataIsStale {
                        Log.error("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        Crashlytics.crashlytics().log("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        staleBookmarks.appendIfNotContains(key)
                    } else {
                        Crashlytics.crashlytics().log("Resolved bookmark: \(key)")
                        Log.info("Resolved bookmark: \(key)")
                        let res = urlForBookmark.startAccessingSecurityScopedResource()
                        if res == true {
                            Crashlytics.crashlytics().log("success: startAccessingSecurityScopedResource for: \(key)")
                            Log.info("success: startAccessingSecurityScopedResource for: \(key)")
                            resolvedBookmarks.append(urlForBookmark)
                            bookmarks.append([urlForBookmark.absoluteString: urlData])
                        } else {
                            Crashlytics.crashlytics().log("ERROR: startAccessingSecurityScopedResource for: \(key)")
                            Log.error("ERROR: startAccessingSecurityScopedResource for: \(key)")
                            staleBookmarks.appendIfNotContains(key)
                        }
                    }
                } catch {
                    staleBookmarks.appendIfNotContains(key)
                    Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                    Log.error("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                }
            }
        }

        // reset bookmarks
        iChangedTheBookmarks = true
        prefs.set(bookmarks, forKey: SASecureBookmarks)
        prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
    }

    /// addBookmark 
    ///  - Parameters:
    ///	 - url: file URL to generate secure bookmark for
    ///	 - options: URL.BookmarkCreationOptions. see https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions
    ///  - isForStaleBookmark: Bool stating if this add bookmark call is for a stale bookmark
    /// - Returns: Bool on success or fail
    @objc func addBookmarkFor(url: URL, options: UInt, isForStaleBookmark: Bool) -> Bool {
        let bookmarkCreationOptions: URL.BookmarkCreationOptions = URL.BookmarkCreationOptions(rawValue: options)

        // A file chosen from an NSOpen/SavePanel already has access
        // no need to start access again here again here
        Crashlytics.crashlytics().log("Adding bookmark for: \(url.absoluteString)")


        for (index, bookmarkDict) in bookmarks.enumerated() {
            if bookmarkDict[url.absoluteString] != nil {
                if isForStaleBookmark == false {
                    Crashlytics.crashlytics().log("Existing bookmark for: \(url.absoluteString)")
                    Log.debug("Existing bookmark for: \(url.absoluteString)")
                    return true
                }
                else{
                    // JCS - Not sure we'll ever get here
                    Crashlytics.crashlytics().log("Removing existing STALE bookmark for: \(url.absoluteString)")
                    Log.debug("Removing existing STALE bookmark for: \(url.absoluteString)")
                    if bookmarks[safe: index] != nil{
                        bookmarks.remove(at: index)
                    }
                    break
                }
            }
        }

        do {
            // any errors are caught below in the catch{}
            Crashlytics.crashlytics().log("Attempting to create secure bookmark for: \(url.absoluteString) - with bookmarkCreationOptions:\(bookmarkCreationOptions.rawValue)")
            Log.debug("Attempting to create secure bookmark for: \(url.absoluteString) - with bookmarkCreationOptions:\(bookmarkCreationOptions.rawValue)")
            let bookmarkData = try url.bookmarkData(options: [bookmarkCreationOptions], includingResourceValuesForKeys: nil, relativeTo: nil)

            Log.debug("Attempting to create SecureBookmark object for: \(url.absoluteString)")
            Crashlytics.crashlytics().log("Attempting to create SecureBookmark object for: \(url.absoluteString)")
            let sp = SecureBookmark(data: bookmarkData, options: Double(bookmarkCreationOptions.rawValue), url: url)

            Crashlytics.crashlytics().log("Attempting getEncodedData for: \(sp.debugDescription)")
            Log.debug("Attempting getEncodedData for: \(sp.debugDescription)")
            guard let spData = sp.getEncodedData() else {
                Log.error("Failed to getEncodedData for: \(sp.debugDescription)")
                Crashlytics.crashlytics().log("Failed to getEncodedData for: \(sp.debugDescription)")
                return false
            }

            Log.debug("SUCCESS: Adding \(url.absoluteString) to bookmarks")
            Crashlytics.crashlytics().log("SUCCESS: Adding \(url.absoluteString) to bookmarks")
            bookmarks.append([url.absoluteString: spData])
            resolvedBookmarks.append(url)

            if(staleBookmarks.contains(url.absoluteString)){
                Log.debug("Removing stale bookmark for: \(url.absoluteString)")
                Log.debug("staleBookmarks count = \(staleBookmarks.count)")
                staleBookmarks.removeAll(where: { $0 == url.absoluteString })
                Log.debug("staleBookmarks count = \(staleBookmarks.count)")
            }

            Log.debug("Updating UserDefaults")
            Crashlytics.crashlytics().log("Updating UserDefaults")
            iChangedTheBookmarks = true
            prefs.set(bookmarks, forKey: SASecureBookmarks)
            prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)

            return true

        } catch {
            Log.error("Error creating secure Bookmark For: key = \(url.absoluteString). Error: \(error.localizedDescription)")
            Crashlytics.crashlytics().log("Error creating secure Bookmark For: key = \(url.absoluteString). Error: \(error.localizedDescription)")
            return false
        }
    }

    /// bookmarkFor a file
    ///  - Parameters:
    ///     - filename: file URL to generate secure bookmark for
    /// - Returns: the resolved URL or nil
    @objc func bookmarkFor(filename: String) -> URL? {
        Log.debug("filename: \(filename)")

        for bookmarkDict in bookmarks {
            for (key, urlData) in bookmarkDict {
                Log.info("Bookmark URL = \(key)")

                if key == filename {
                    do {
                        var bookmarkDataIsStale = false

                        Log.debug("Attempting to getDecodedData for: \(key)")
                        Crashlytics.crashlytics().log("Attempting to getDecodedData for: \(key)")
                        let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                        Log.debug("Attempting to resolve bookmark data for: \(key)")
                        Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                        // always resolve with just URLBookmarkResolutionWithSecurityScope
                        let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                        if bookmarkDataIsStale {
                            Log.error("The bookmark is outdated and needs to be regenerated: key = \(key)")
                            Crashlytics.crashlytics().log("The bookmark is outdated and needs to be regenerated: key = \(key)")
                            staleBookmarks.appendIfNotContains(key)
                            prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
                        } else {
                            if urlForBookmark.startAccessingSecurityScopedResource() {
                                resolvedBookmarks.append(urlForBookmark)
                                return urlForBookmark
                            } else {
                                Log.error("Error startAccessingSecurityScopedResource For: key = \(urlForBookmark.absoluteString).")
                                Crashlytics.crashlytics().log("Error startAccessingSecurityScopedResource For: key = \(urlForBookmark.absoluteString).")
                                return nil
                            }
                        }
                    } catch {
                        Log.error("Error resolving bookmark: filename = \(filename). Error: \(error.localizedDescription)")
                        Crashlytics.crashlytics().log("Error resolving bookmark: filename = \(filename). Error: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
        }

        Log.info("No bookmark found for: \(filename)")
        Crashlytics.crashlytics().log("No bookmark found for: \(filename)")
        return nil
    }

    /// revokeBookmark
    ///  - Parameters:
    ///     - filename: filename to revoke secure bookmark for
    /// - Returns: Bool on success or fail
    @objc func revokeBookmark(filename: String) -> Bool {

        var found = false

        for (index, bookmarkDict) in bookmarks.enumerated() {
            for (key, urlData) in bookmarkDict {
                if key == filename {

                    found = true

                    do {
                        Log.debug("Revoking bookmark for: \(filename)")
                        Crashlytics.crashlytics().log("Revoking bookmark for: \(filename)")
                        Log.debug("bookmarks[\(index)]: \(bookmarks[index])")

                        var bookmarkDataIsStale = false

                        // need to get the proper URL
                        let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                        Log.debug("Attempting to resolve bookmark data for: \(key)")
                        Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                        // always resolve with just URLBookmarkResolutionWithSecurityScope
                        let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                        // you do not need to call .stopAccessingSecurityScopedResource()
                        // simply remove from bookmarks
                        // FIXME: ACTUALLY ... DO WE NEED ALL THIS? just remove from bookmarks

                        resolvedBookmarks.removeAll(where: { $0 == urlForBookmark })
                        if bookmarks[safe: index] != nil{
                            bookmarks.remove(at: index)
                        }
                        iChangedTheBookmarks = true
                        prefs.set(bookmarks, forKey: SASecureBookmarks)
                        Log.debug("Successfully revoked bookmark for: \(filename)")
                        Crashlytics.crashlytics().log("Successfully revoked bookmark for: \(filename)")

                        // if it was in stalebookmarks, remove
                        if(staleBookmarks.contains(key)){
                            Log.debug("Removing stale bookmark for: \(key)")
                            staleBookmarks.removeAll(where: { $0 == key })
                            prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
                        }

                        return true
                    } catch {
                        Log.error("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                        Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                        Log.error("Failed to revoke bookmark for: \(filename)")
                        Crashlytics.crashlytics().log("Failed to revoke bookmark for: \(filename)")
                        // should we remove from bookmarks here?

                        return false
                    }
                }
            }
        }

        if found == false{
            Crashlytics.crashlytics().log("No bookmark found for: \(filename)")
            Log.info("No bookmark found for: \(filename)")

            // it's not in bookmarks, but is in staleBookmarks, just remove it
            if(staleBookmarks.contains(filename)){
                Log.debug("Removing stale bookmark for: \(filename)")
                staleBookmarks.removeAll(where: { $0 == filename })
                prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
                return true
            }
        }

        // if you try to revoke a stale bookmark ... you get to here
        // and can never remove it...
        Log.debug("found: \(found)")
        Log.error("Failed to revoke bookmark for: \(filename)")
        Crashlytics.crashlytics().log("Failed to revoke bookmark for: \(filename)")
        return false
    }

    // revoke secure access to all bookmarks
    @objc func stopAllSecurityScopedAccess() {
        Log.debug("stopAllSecurityScopedAccess called")
        Log.debug("resolvedBookmarks count = \(resolvedBookmarks.count)")
        Crashlytics.crashlytics().log("resolvedBookmarks count = \(resolvedBookmarks.count)")
        Crashlytics.crashlytics().log("stopAllSecurityScopedAccess called")

        for url in resolvedBookmarks {
            resolvedBookmarks.removeAll(where: { $0 == url })
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        observer?.invalidate()
    }
}
