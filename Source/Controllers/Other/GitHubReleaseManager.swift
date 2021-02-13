//
//  GitHubReleaseManager.swift
//  Sequel Ace
//
//  Created by James on 12/2/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Foundation
import OSLog
import Alamofire

@objc final class GitHubReleaseManager: NSObject {
    static let NSModalResponseView    : NSApplication.ModalResponse = NSApplication.ModalResponse(rawValue: 1001);
    static let NSModalResponseDownload: NSApplication.ModalResponse = NSApplication.ModalResponse(rawValue: 1002);

    @objc static let sharedInstance                     = GitHubReleaseManager()
    static let githubURLStr           : String          = "https://api.github.com/repos/%@/%@/releases"
    private var user                  : String
    private var project               : String
    private var includeDraft          : Bool
    private var includePrerelease     : Bool
    private var currentReleaseName    : String = ""
    private var availableReleaseName  : String = ""
    private var currentRelease        : GitHubElement?
    private var availableRelease      : GitHubElement?
    private var releases              : [GitHubElement] = []
    private let Log                                     = OSLog(subsystem : "com.sequel-ace.sequel-ace", category : "github")


    struct Config {
        var user              : String
        var project           : String
        var includeDraft      : Bool = false
        var includePrerelease : Bool = false
    }

    private static var config:Config?

    class func setup(_ config:Config){
        GitHubReleaseManager.config = config
    }

    private override init() {
        guard let config = GitHubReleaseManager.config else {
            Log.error("you must call setup before accessing GitHubReleaseManager.sharedInstance")
            fatalError("Error - you must call setup before accessing GitHubReleaseManager.sharedInstance")
        }

        self.user              = config.user
        self.project           = config.project
        self.includeDraft      = config.includeDraft
        self.includePrerelease = config.includePrerelease

        Log.debug("GitHubReleaseManager init")

        super.init()
    }

    public func checkReleaseWithName(name: String){

        Log.debug("checkReleaseWithName: \(name)")

        let urlStr = GitHubReleaseManager.githubURLStr.format(user, project)

        Log.debug("GitHubReleaseManager.config = \(String(describing: GitHubReleaseManager.config))")
        Log.debug("urlStr = \(urlStr)")

        AF.request(urlStr){ urlRequest in
            urlRequest.timeoutInterval = 60
            self.Log.debug("urlRequest: \(urlRequest)")
        }
        .validate() // check response code etc
        .responseJSON { [self] response in
            switch response.result {
                case .success:
                    Log.info("Validation Successful")

                    do{
                        guard let responseData = response.data else {
                            Log.error("response.data not valid")
                            return
                        }
                        
                        let json = try JSONSerialization.jsonObject(with: responseData, options: JSONSerialization.ReadingOptions())
                        let jsonData = try JSONSerialization.data(withJSONObject: json, options: .fragmentsAllowed)
                        let gitHub = try GitHub(data: jsonData)

                        var releasesArray = gitHub.sorted(by: { (element0: GitHubElement, element1: GitHubElement) -> Bool in
                            return element0 > element1
                        })

                        Log.debug("releasesArray count: \(releasesArray.count)")

                        if let i = releasesArray.firstIndex(where: { $0.name == name }) {
                            currentRelease = releasesArray[i]
                            guard let currentReleaseName = currentRelease?.name else {
                                 return
                            }
                            self.currentReleaseName = currentReleaseName
                            Log.debug("Found this release at index:[\(i)] name: \(currentReleaseName))")
                        }

                        if includeDraft == false {
                            // remove drafts
                            Log.debug("removing drafts")
                            releasesArray.removeAll(where: { $0.draft == true })
                        }

                        if includePrerelease == false {
                            // remove prereleases
                            Log.debug("removing prereleases")
                            releasesArray.removeAll(where: { $0.prerelease == true })
                        }

                        Log.debug("releasesArray count: \(releasesArray.count)")

                        releases = releasesArray
                        availableRelease = releases.first
                        if availableRelease != currentRelease {
                            guard let availableReleaseName = availableRelease?.name else {
                                 return
                            }
                            self.availableReleaseName = availableReleaseName
                            Log.info("Found availableRelease: \(availableReleaseName)")
                            // ??? do we need this?
                            NotificationCenter.default.post(name: Notification.Name(NSNotification.Name.SPNewReleaseAvailable.rawValue), object: availableRelease)
                            _ = self.displayNewReleaseAvailableAlert()
                        }
                    }
                    catch{
                        Log.error("Error: \(error.localizedDescription)")
                    }

                case let .failure(error):
                    Log.error("Error: \(error.localizedDescription)")
            }
        }
    }

    private func displayNewReleaseAvailableAlert() -> Bool {

        Log.debug("displayNewReleaseAvailableAlert")

        let prefs    : UserDefaults = UserDefaults.standard
        var localURL : URL
        let message  : String
        var asset    : Asset?

        if prefs.string(forKey: SPSkipNewReleaseAvailable) == availableReleaseName {
            Log.debug("The user has opted out of more alerts regarding this version")
            return false
        }

        if (availableRelease?.htmlURL == nil) {
            Log.error("release has no url")
            return false
        }

        guard
            let availableReleaseURL = availableRelease?.htmlURL,
            let url = URL(string: availableReleaseURL)
        else {
            return false
        }

        localURL = url

        if let i = availableRelease?.assets.firstIndex(where: { $0.browserDownloadURL.count > 0 }) {
            asset = availableRelease?.assets[i] ?? nil
        }

        message = NSLocalizedString("Version %@ is available. You are currently running %@",
                                    comment: "Version %@ is available. You are currently running %@") .format(availableReleaseName, currentReleaseName)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("A new version is available", comment: "A new version is available")
        alert.informativeText = message
        alert.showsSuppressionButton = true
        alert.alertStyle = .informational
        alert.addButton(withTitle: "View").tag = GitHubReleaseManager.NSModalResponseView.rawValue
        
        if asset != nil {
            alert.addButton(withTitle: NSLocalizedString("Download", comment: "Download new version")).tag = GitHubReleaseManager.NSModalResponseDownload.rawValue
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button")).tag = NSApplication.ModalResponse.cancel.rawValue

        guard let mainWindow = NSApp.mainWindow else { return false }

        alert .beginSheetModal(for: mainWindow) { [self] (returnCode: NSApplication.ModalResponse) -> Void in
            self.Log.debug("returnCode: \(returnCode)")

            if let suppressionButton = alert.suppressionButton,
               suppressionButton.state == .on {
                prefs.setValue(self.availableReleaseName, forKey: SPSkipNewReleaseAvailable)
            }

            switch returnCode {
                case GitHubReleaseManager.NSModalResponseView:
                    self.Log.debug("user clicked view")
                    NSWorkspace.shared .open(localURL)
                case GitHubReleaseManager.NSModalResponseDownload:
                    self.Log.debug("user clicked download")
                    self.downloadNewRelease(asset: asset!) // already checked that this is not nil
                case NSApplication.ModalResponse.cancel:
                    self.Log.debug("user clicked cancel")
                default:
                    return
            }
        }

        return true
    }

    private func downloadNewRelease(asset: Asset){
        self.Log.debug("downloadNewRelease")

        self.Log.debug("asset.browserDownloadURL: \(asset.browserDownloadURL)")

        let downloadNSString : NSString = asset.browserDownloadURL as NSString

        self.Log.debug("asset.browserDownloadURL: \(downloadNSString.lastPathComponent)")


        let destination: DownloadRequest.Destination = { _, _ in
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let fileURL = downloadsURL.appendingPathComponent(downloadNSString.lastPathComponent)
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        var previousFractionCompleted : Double = 0.0

        AF.download(asset.browserDownloadURL, to: destination)
            .downloadProgress { progress in
                self.Log.debug("Download Progress: \(progress.fractionCompleted)")
                previousFractionCompleted = progress.fractionCompleted - previousFractionCompleted
                self.Log.debug("previousFractionCompleted: \(previousFractionCompleted)")
                previousFractionCompleted = progress.fractionCompleted
                if progress.fractionCompleted == 1.0 {
                    self.Log.debug("Download Complete")
                }
            }
            .response { response in
                self.Log.debug("response: \(response)")

                if response.error == nil, let filePath = response.fileURL?.path {
                    self.Log.debug("downloadNewRelease: \(filePath)")
                }
            }
    }

}
