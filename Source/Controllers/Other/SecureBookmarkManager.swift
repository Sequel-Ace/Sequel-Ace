//
//  SecureBookmarkManager.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

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
    @objc static let sharedInstance                    = SecureBookmarkManager()

    @objc var bookmarks: [Dictionary<String, Data>]    = []
    @objc var staleBookmarks: [String]                 = []

    @objc var resolvedBookmarks: [URL]                 = []
    @objc var knownHostsBookmarks: [String]               = []
    private let URLBookmarkResolutionWithSecurityScope = URL.BookmarkResolutionOptions(rawValue: 1 << 10)
    private let URLBookmarkCreationWithSecurityScope   = URL.BookmarkCreationOptions(rawValue: 1 << 11)

    private let prefs: UserDefaults                    = UserDefaults.standard
    private var observer: NSKeyValueObservation?

    private var iChangedTheBookmarks: Bool             = false
    private var bookmarksHaveBeenMigrated: Bool        = false
    private let Log                                    = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "secureBookmarks")


    override init() {

        Log.info("SecureBookmarkManager init.")
        Log.info("OSLog.Options.defaultPrivacy: \(OSLog.Options.defaultPrivacy)")
        Log.info("OSLog.Options.logFileName: \(OSLog.Options.logFileName)")

        super.init()

        // this manager *should* be the only thing changing the bookmarks pref, but in case...
        observer = UserDefaults.standard.observe(\.SPSecureBookmarks, options: [.new, .old], changeHandler: { [self] _, change in

            if iChangedTheBookmarks == false {
                Log.debug("SPSecureBookmarks changed, but NOT by SecureBookmarkManager.")
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
            return
        }

        staleBookmarks = prefs.array(forKey: SPStaleSecureBookmarks) as? [String] ?? []
        knownHostsBookmarks = prefs.array(forKey: SPKnownHostsBookmarks) as? [String] ?? []

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
                    // always resolve with just URLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: urlData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                    if bookmarkDataIsStale {
                        Log.error("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        staleBookmarks.appendIfNotContains(key)
                        continue
                    } else {
                        Log.info("Resolved bookmark: \(key)")
                    }

                    Log.debug("Attempting to create SecureBookmark object for: \(urlForBookmark.absoluteString)")
                    // NSURLBookmarkCreationWithSecurityScope is a guess .. could be read only, BUT read only fails to resolve! so it has to be securityScope
                    let sp = SecureBookmark(data: urlData, options: Double(URLBookmarkCreationWithSecurityScope.rawValue), url: urlForBookmark)

                    Log.debug("Attempting getEncodedData for: \(sp.debugDescription)")

                    guard let spData = sp.getEncodedData() else {
                        Log.error("Failed to getEncodedData for: \(sp.debugDescription)")
                        staleBookmarks.appendIfNotContains(key)
                        continue
                    }

                    Log.debug("SUCCESS: Migrated: \(urlForBookmark.absoluteString)")
                    migratedBookmarks.append([urlForBookmark.absoluteString: spData])

                }
                catch {
                    staleBookmarks.appendIfNotContains(key)
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
    // otherwise it will be marked as stale.
    private func reRequestSecureAccessToBookmarks() {

        // re-read - must do this after migration, could put it in an if, but it only happens once per app start.
        guard let secureBookmarks = prefs.array(forKey: SASecureBookmarks) as? [[String: Data]], secureBookmarks.isNotEmpty else {
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

                    Log.debug("Attempting to getDecodedData for: \(key)")
                    let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                    Log.debug("Attempting to resolve bookmark data for: \(key)")
                    // always resolve with just URLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                    //a bookmark might be "stale" because the app hasn't been used
                    //in many months, macOS has been upgraded, the app was
                    //re-installed, the app's preferences .plist file was deleted, etc.
                    if bookmarkDataIsStale {
                        Log.error("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        staleBookmarks.appendIfNotContains(key)
                    } else {
                        Log.info("Resolved bookmark: \(key)")
                        let res = urlForBookmark.startAccessingSecurityScopedResource()
                        if res == true {
                            Log.info("success: startAccessingSecurityScopedResource for: \(key)")
                            resolvedBookmarks.appendIfNotContains(urlForBookmark)
                            bookmarks.append([urlForBookmark.absoluteString: urlData])
                        } else {
                            Log.error("ERROR: startAccessingSecurityScopedResource for: \(key)")
                            staleBookmarks.appendIfNotContains(key)
                        }
                    }
                } catch {
                    staleBookmarks.appendIfNotContains(key)
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
    @objc func addBookmarkFor(url: URL, options: UInt, isForStaleBookmark: Bool, isForKnownHostsFile: Bool) -> Bool {
        let bookmarkCreationOptions: URL.BookmarkCreationOptions = URL.BookmarkCreationOptions(rawValue: options)

        let possibleMatchingStrings = [
            url.absoluteString,
            url.absoluteString.removingPercentEncoding!
        ]

        Log.debug("isForStaleBookmark: \(isForStaleBookmark)")
        Log.debug("isForKnownHostsFile: \(isForKnownHostsFile)")


        for (index, bookmarkDict) in bookmarks.enumerated() {
            for posibility in possibleMatchingStrings {
                if bookmarkDict[posibility] != nil {
                    if isForStaleBookmark == false {
                        Log.debug("Existing bookmark for: \(url.absoluteString)")
                        if isForKnownHostsFile == true {
                            knownHostsBookmarks.appendIfNotContains(url.absoluteString)
                            Log.debug("Updating UserDefaults for SPKnownHostsBookmarks")
                            prefs.set(knownHostsBookmarks, forKey: SPKnownHostsBookmarks)
                        }
                        return true
                    }
                    else{
                        // JCS - Not sure we'll ever get here
                        Log.debug("Removing existing STALE bookmark for: \(url.absoluteString)")
                        if bookmarks[safe: index] != nil{
                            bookmarks.remove(at: index)
                        }
                    }
                }
            }
        }

        do {
            // any errors are caught below in the catch{}
            Log.debug("Attempting to create secure bookmark for: \(url.absoluteString) - with bookmarkCreationOptions:\(bookmarkCreationOptions.rawValue)")
            let bookmarkData = try url.bookmarkData(options: [bookmarkCreationOptions], includingResourceValuesForKeys: nil, relativeTo: nil)

            Log.debug("Attempting to create SecureBookmark object for: \(url.absoluteString)")
            let sp = SecureBookmark(data: bookmarkData, options: Double(bookmarkCreationOptions.rawValue), url: url)

            Log.debug("Attempting getEncodedData for: \(sp.debugDescription)")
            guard let spData = sp.getEncodedData() else {
                Log.error("Failed to getEncodedData for: \(sp.debugDescription)")
                return false
            }

            Log.debug("SUCCESS: Adding \(url.absoluteString) to bookmarks")
            bookmarks.append([url.absoluteString: spData])
            resolvedBookmarks.appendIfNotContains(url)

            if staleBookmarks.contains(url.absoluteString) {
                Log.debug("Removing stale bookmark for: \(url.absoluteString)")
                Log.debug("staleBookmarks count = \(staleBookmarks.count)")
                staleBookmarks.removeAll(where: { $0 == url.absoluteString })
                Log.debug("staleBookmarks count = \(staleBookmarks.count)")
            }

            if isForKnownHostsFile == true {
                Log.debug("Adding KnownHostsFile bookmark for: \(url.absoluteString)")
                knownHostsBookmarks.appendIfNotContains(url.absoluteString)
            }

            Log.debug("Updating UserDefaults")
            iChangedTheBookmarks = true
            prefs.set(bookmarks, forKey: SASecureBookmarks)
            prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
            prefs.set(knownHostsBookmarks, forKey: SPKnownHostsBookmarks)

            return true

        } catch {
            Log.error("Error creating secure Bookmark For: key = \(url.absoluteString). Error: \(error.localizedDescription)")
            return false
        }
    }

    /// bookmarkFor a file
    ///  - Parameters:
    ///     - filename: file URL to return secure bookmark for
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
                        let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                        Log.debug("Attempting to resolve bookmark data for: \(key)")
                        // always resolve with just URLBookmarkResolutionWithSecurityScope
                        let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                        if bookmarkDataIsStale {
                            Log.error("The bookmark is outdated and needs to be regenerated: key = \(key)")
                            staleBookmarks.appendIfNotContains(key)
                            prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
                        } else {
                            if urlForBookmark.startAccessingSecurityScopedResource() {
                                resolvedBookmarks.appendIfNotContains(urlForBookmark)
                                return urlForBookmark
                            } else {
                                Log.error("Error startAccessingSecurityScopedResource For: key = \(urlForBookmark.absoluteString).")
                                return nil
                            }
                        }
                    } catch {
                        Log.error("Error resolving bookmark: filename = \(filename). Error: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
        }

        Log.info("No bookmark found for: \(filename)")
        return nil
    }

    /// revokeBookmark
    ///  - Parameters:
    ///     - filename: filename to revoke secure bookmark for
    /// - Returns: Bool on success or fail
    @objc func revokeBookmark(filename: String) -> Bool {

        var found = false

        let sanitizedFilename = filename.removingPercentEncoding?.dropPrefix("file://")


        //Handle known hosts first
        let initialKnownHostsBookmarksCount = knownHostsBookmarks.count
        knownHostsBookmarks.removeAll(where: { $0.removingPercentEncoding?.dropPrefix("file://") == sanitizedFilename })
        if(initialKnownHostsBookmarksCount != knownHostsBookmarks.count){
            Log.debug("Removed knownHosts bookmark for: \(filename)")
            prefs.set(knownHostsBookmarks, forKey: SPKnownHostsBookmarks)
            found = true
        }

        //Then handle stale bookmarks
        // if it was in stalebookmarks, remove
        let initialStaleBookmarksCount = staleBookmarks.count
        staleBookmarks.removeAll(where: { $0.removingPercentEncoding?.dropPrefix("file://") == sanitizedFilename })
        if(initialStaleBookmarksCount != staleBookmarks.count){
            Log.debug("Removed stale bookmark for: \(filename)")
            prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
            found = true
        }


        //Then handle standard bookmarks
        for (index, bookmarkDict) in bookmarks.enumerated() {
            for (key, urlData) in bookmarkDict {
                if key.removingPercentEncoding?.dropPrefix("file://") == sanitizedFilename {

                    found = true

                    do {
                        Log.debug("Revoking bookmark for: \(filename)")
                        Log.debug("bookmarks[\(index)]: \(bookmarks[index])")

                        var bookmarkDataIsStale = false

                        // need to get the proper URL
                        let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                        Log.debug("Attempting to resolve bookmark data for: \(key)")
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

                        break
                    } catch {
                        Log.error("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                        Log.error("Failed to revoke bookmark for: \(filename)")
                        // should we remove from bookmarks here?

                        return false
                    }
                }
            }
        }

        if(found) {
            NotificationCenter.default.post(name: Notification.Name(NSNotification.Name.SPBookmarksChanged.rawValue), object: self)
        } else {
            // if you try to revoke a stale bookmark ... you get to here
            // and can never remove it...
            Log.debug("found: \(found)")
            Log.error("Failed to revoke bookmark for: \(filename)")
        }


        return found
    }

    @objc func addStaleBookmark(filename: String){
        Log.debug("addStaleBookmark called")
        staleBookmarks.appendIfNotContains(filename)
        prefs.set(staleBookmarks, forKey: SPStaleSecureBookmarks)
        Log.info("staleBookmarks count = \(staleBookmarks.count)")
        // post notificay for SPFilePreferencePane
        NotificationCenter.default.post(name: Notification.Name(NSNotification.Name.SPBookmarksChanged.rawValue), object: self)
    }

    @objc func addKnownHostsBookmark(filename: String){
        Log.debug("addKnownHostsBookmark called")
        knownHostsBookmarks.appendIfNotContains(filename)
        prefs.set(knownHostsBookmarks, forKey: SPKnownHostsBookmarks)
        Log.info("knownHostsBookmarks count = \(knownHostsBookmarks.count)")
    }

    // revoke secure access to all bookmarks
    @objc func stopAllSecurityScopedAccess() {
        Log.debug("stopAllSecurityScopedAccess called")
        Log.debug("resolvedBookmarks count = \(resolvedBookmarks.count)")

        for url in resolvedBookmarks {
            resolvedBookmarks.removeAll(where: { $0 == url })
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        observer?.invalidate()
    }
}
