//
//  SecureBookmarkManager.swift
//  Sequel Ace
//
//  Created by James on 7/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Firebase
import Foundation
import os.log

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
    @objc private var resolvedBookmarks: [URL] = []

    private let URLBookmarkResolutionWithSecurityScope = URL.BookmarkResolutionOptions(rawValue: 1 << 10)
    private let log: OSLog
    private let prefs: UserDefaults = UserDefaults.standard
    private var observer: NSKeyValueObservation?

    private var iChangedTheBookmarks: Bool = false

    override init() {
        log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "secureBookmarks")

        os_log("SecureBookmarkManager init.", log: log, type: .info)
        Crashlytics.crashlytics().log("SecureBookmarkManager init.")

        super.init()

        // this manager *should* be the only thing changing the bookmarks pref, but in case...
        observer = UserDefaults.standard.observe(\.SPSecureBookmarks, options: [.new, .old], changeHandler: { _, change in

            if self.iChangedTheBookmarks == false {
                os_log("SPSecureBookmarks changed NOT by SecureBookmarkManager.", log: self.log, type: .debug)
                Crashlytics.crashlytics().log("SPSecureBookmarks changed NOT by SecureBookmarkManager.")
                self.bookmarks.removeAll()
                self.bookmarks = change.newValue!
            }
            // reset
            self.iChangedTheBookmarks = false

            // post notificay for ConnectionController
            NotificationCenter.default.post(name: Notification.Name(NSNotification.Name.SPBookmarksChanged.rawValue), object: self)

        })

        // FIXME: @Kaspik need help ... need a guard or if let, don't want the default value...

        guard let secureBookmarks = prefs.array(forKey: SASecureBookmarks) as? [[String: Data]], secureBookmarks.isNotEmpty else {
            os_log("Could not get secureBookmarks from prefs.", log: log, type: .error)
            Crashlytics.crashlytics().log("Could not get secureBookmarks from prefs.")
            return
        }

        bookmarks = secureBookmarks

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
    // URLBookmarkResolutionWithSecurityScope, not the options it was originally created with
    // otherwise it will be markes as stale.
    @objc func reRequestSecureAccessToBookmarks() {
        let bmCopy = bookmarks

        // start afresh
        bookmarks.removeAll()

        for bookmarkDict in bmCopy {
            for (key, urlData) in bookmarkDict {
                os_log("Bookmark URL = %@", log: log, type: .info, key)

                do {
                    var bookmarkDataIsStale = false

                    os_log("Attempting to getDecodedData for %@", log: log, type: .debug, key)
                    Crashlytics.crashlytics().log("Attempting to getDecodedData for: \(key)")
                    let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                    os_log("Attempting to resolve bookmark data for %@", log: log, type: .debug, key)
                    Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                    // always resolve with just URLBookmarkResolutionWithSecurityScope
                    let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

//                   bookmarkDataIsStale = true
                    //a bookmark might be "stale" because the app hasn't been used
                    //in many months, macOS has been upgraded, the app was
                    //re-installed, the app's preferences .plist file was deleted, etc.
                    if bookmarkDataIsStale {
                        os_log("The bookmark is outdated and needs to be regenerated: key = %@", log: log, type: .error, key)
                        Crashlytics.crashlytics().log("The bookmark is outdated and needs to be regenerated: key = \(key)")
                        staleBookmarks.append(key)
                    } else {
                        os_log("Resolved bookmark: %@", log: log, type: .info, key)
                        Crashlytics.crashlytics().log("Resolved bookmark: \(key)")
                        let res = urlForBookmark.startAccessingSecurityScopedResource()
                        if res == true {
                            os_log("success: startAccessingSecurityScopedResource for: %@", log: log, type: .info, key)
                            Crashlytics.crashlytics().log("success: startAccessingSecurityScopedResource for: \(key)")
                            resolvedBookmarks.append(urlForBookmark)
                            bookmarks.append([urlForBookmark.absoluteString: urlData])
                        } else {
                            os_log("ERROR: startAccessingSecurityScopedResource for: %@", log: log, type: .info, key)
                            Crashlytics.crashlytics().log("ERROR: startAccessingSecurityScopedResource for: \(key)")
                            staleBookmarks.append(key)
                        }
                    }
                } catch {
                    staleBookmarks.append(key)
                    os_log("Error resolving bookmark: key = %@. Error: %@", log: log, type: .error, key, error.localizedDescription)
                    Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                }
            }
        }

        // reset bookmarks
        iChangedTheBookmarks = true
        prefs.set(bookmarks, forKey: SASecureBookmarks)
    }

    /// addBookMark
    ///  - Parameters:
    ///	 - url: file URL to generate secure bookmark for
    ///	 - options: URL.BookmarkCreationOptions. see https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions
    /// - Returns: Bool on success or fail
    @objc public func addBookMarkFor(url: URL, options: UInt) -> Bool {
        let bookmarkCreationOptions: URL.BookmarkCreationOptions = URL.BookmarkCreationOptions(rawValue: options)

        // A file chosen from an NSOpen/SavePanel already has access
        // no need to start access again here again here

        for bookmarkDict in bookmarks {
            if bookmarkDict[url.absoluteString] != nil {
                os_log("Existing bookmark for: %@", log: log, type: .debug, url.absoluteString)
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

            os_log("SUCCESS: Adding %@ to bookmarks", log: log, type: .debug, url.absoluteString)
            Crashlytics.crashlytics().log("SUCCESS: Adding \(url.absoluteString) to bookmarks")
            bookmarks.append([url.absoluteString: spData])

            os_log("Updating UserDefaults", log: log, type: .debug)
            Crashlytics.crashlytics().log("Updating UserDefaults")
            iChangedTheBookmarks = true
            prefs.set(bookmarks, forKey: SASecureBookmarks)

            return true

        } catch {
            os_log("Error creating secure Bookmark For: key = %@. Error: %@", log: log, type: .error, url.absoluteString, error.localizedDescription)
            Crashlytics.crashlytics().log("Error creating secure Bookmark For: key = \(url.absoluteString). Error: \(error.localizedDescription)")
            return false
        }
    }

    /// bookMarkFor a file
    ///  - Parameters:
    ///     - filename: file URL to generate secure bookmark for
    /// - Returns: the resolved URL or nil
    @objc public func bookMarkFor(filename: String) -> URL? {
        os_log("filename %@", log: log, type: .debug, filename)

        for bookmarkDict in bookmarks {
            for (key, urlData) in bookmarkDict {
                os_log("Bookmark URL = %@", log: log, type: .info, key)

                if key == filename {
                    do {
                        var bookmarkDataIsStale = false

                        os_log("Attempting to getDecodedData for %@", log: log, type: .debug, key)
                        Crashlytics.crashlytics().log("Attempting to getDecodedData for: \(key)")
                        let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                        os_log("Attempting to resolve bookmark data for %@", log: log, type: .debug, key)
                        Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                        // always resolve with just URLBookmarkResolutionWithSecurityScope
                        let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                        if bookmarkDataIsStale {
                            os_log("The bookmark is outdated and needs to be regenerated: key = %@", log: log, type: .error, key)
                            Crashlytics.crashlytics().log("The bookmark is outdated and needs to be regenerated: key = \(key)")
                            staleBookmarks.append(key)
                        } else {
                            if urlForBookmark.startAccessingSecurityScopedResource() {
                                return urlForBookmark
                            } else {
                                os_log("Error startAccessingSecurityScopedResource For: key = %@.", log: log, type: .error, urlForBookmark.absoluteString)
                                Crashlytics.crashlytics().log("Error startAccessingSecurityScopedResource For: key = \(urlForBookmark.absoluteString).")
                                return nil
                            }
                        }
                    } catch {
                        os_log("Error resolving bookmark: filename = %@. Error: %@", log: log, type: .error, filename, error.localizedDescription)
                        Crashlytics.crashlytics().log("Error resolving bookmark: filename = \(filename). Error: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
        }

        os_log("No bookmark found for %@", log: log, type: .info, filename)
        Crashlytics.crashlytics().log("No bookmark found for: \(filename)")
        return nil
    }

    /// revokeBookmark
    ///  - Parameters:
    ///     - filename: filename to revoke secure bookmark for
    /// - Returns: Bool on success or fail
    @objc func revokeBookmark(filename: String) -> Bool {
        for (index, bookmarkDict) in bookmarks.enumerated() {
            for (key, urlData) in bookmarkDict {
                if key == filename {
                    do {
                        os_log("Revoking bookmark for: %@", log: log, type: .debug, filename)
                        Crashlytics.crashlytics().log("Revoking bookmark for: \(filename)")

                        os_log("bookmarks[%i]: %@", log: log, type: .debug, index, bookmarks[index])

                        var bookmarkDataIsStale = false

                        // need to get the proper URL
                        let spData = SecureBookmark.getDecodedData(encodedData: urlData)

                        os_log("Attempting to resolve bookmark data for %@", log: log, type: .debug, key)
                        Crashlytics.crashlytics().log("Attempting to resolve bookmark data for: \(key)")
                        // always resolve with just URLBookmarkResolutionWithSecurityScope
                        let urlForBookmark = try URL(resolvingBookmarkData: spData.bookmarkData, options: [URLBookmarkResolutionWithSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkDataIsStale)

                        // you do not need to call .stopAccessingSecurityScopedResource()
                        // simply remove from bookmarks

                        resolvedBookmarks.removeAll(where: { $0 == urlForBookmark })
                        bookmarks.remove(at: index)
                        iChangedTheBookmarks = true
                        prefs.set(bookmarks, forKey: SASecureBookmarks)
                        os_log("Successfully revoked bookmark for: %@", log: log, type: .debug, filename)
                        Crashlytics.crashlytics().log("Successfully revoked bookmark for: \(filename)")
                        return true
                    } catch {
                        os_log("Error resolving bookmark: key = %@. Error: %@", log: log, type: .error, key, error.localizedDescription)
                        Crashlytics.crashlytics().log("Error resolving bookmark: key = \(key). Error: \(error.localizedDescription)")
                        os_log("Failed to revoke bookmark for: %@", log: log, type: .debug, filename)
                        Crashlytics.crashlytics().log("Failed to revoke bookmark for: \(filename)")
                        return false
                    }
                }
            }
        }

        os_log("Failed to revoke bookmark for: %@", log: log, type: .debug, filename)
        Crashlytics.crashlytics().log("Failed to revoke bookmark for: \(filename)")
        return false
    }

    // revoke secure access to all bookmarks
    @objc func stopAllSecurityScopedAccess() {
        for url in resolvedBookmarks {
            resolvedBookmarks.removeAll(where: { $0 == url })
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        observer?.invalidate()
    }
}
