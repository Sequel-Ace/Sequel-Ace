//
//  GitHubReleaseManager.swift
//  Sequel Ace
//
//  Created by James on 12/2/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Alamofire
import Foundation
import OSLog

@objc final class GitHubReleaseManager: NSObject {

    static let NSModalResponseView: NSApplication.ModalResponse = NSApplication.ModalResponse(rawValue: 1001)
    static let NSModalResponseDownload: NSApplication.ModalResponse = NSApplication.ModalResponse(rawValue: 1002)
    static let sharedInstance = GitHubReleaseManager()
    static let githubURLStr: String = "https://api.github.com/repos/%@/%@/releases"
    private var user: String
    private var project: String
    private var includeDraft: Bool
    private var includePrerelease: Bool
    private var progressViewController: ProgressViewController?
    private var progressWindowController: ProgressWindowController?
    private var download: DownloadRequest?
    private var currentReleaseName: String = ""
    private var availableReleaseName: String = ""
    private var currentRelease: GitHubElement?
    private var availableRelease: GitHubElement?
    private var releases: [GitHubElement] = []
    private let Log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "github")
    private let manager = NetworkReachabilityManager(host: "www.google.com")
    public var isFromMenuCheck: Bool = false

    struct Config {
        var user: String
        var project: String
        var includeDraft: Bool = false
        var includePrerelease: Bool = false
    }

    private static var config: Config?

    class func setup(_ config: Config) {
        GitHubReleaseManager.config = config
    }

    override private init() {
        guard let config = GitHubReleaseManager.config else {
            Log.error("you must call setup before accessing GitHubReleaseManager.sharedInstance")
            fatalError("Error - you must call setup before accessing GitHubReleaseManager.sharedInstance")
        }

        user = config.user
        project = config.project
        includeDraft = config.includeDraft
        includePrerelease = config.includePrerelease

        Log.debug("GitHubReleaseManager init")

        super.init()

    }

    public func checkRelease(name: String) {
        if name.count == 0 {
            Log.error("name not valid")
            return
        }

        Log.debug("checkRelease: \(name)")

        let urlStr = GitHubReleaseManager.githubURLStr.format(user, project)

        Log.debug("GitHubReleaseManager.config = \(String(describing: GitHubReleaseManager.config))")
        Log.debug("urlStr = \(urlStr)")

        AF.request(urlStr) { urlRequest in
            urlRequest.timeoutInterval = 60
            self.Log.debug("urlRequest: \(urlRequest)")
        }
        .validate() // check response code etc
        .responseJSON { [self] response in
            switch response.result {
            case .success:
                Log.info("Validation Successful")

                do {
                    guard let responseData = response.data else {
                        Log.error("response.data not valid")
                        return
                    }

                    let json = try JSONSerialization.jsonObject(with: responseData, options: JSONSerialization.ReadingOptions())
                    let jsonData = try JSONSerialization.data(withJSONObject: json, options: .fragmentsAllowed)
                    let gitHub = try GitHub(data: jsonData)

                    var releasesArray = gitHub.sorted(by: { (element0: GitHubElement, element1: GitHubElement) -> Bool in
                        element0 > element1
                    })

                    Log.debug("releasesArray count: \(releasesArray.count)")

                    if let currentReleaseTmp = releasesArray.first(where: { $0.name.hasPrefix(name) == true}) {
                        currentRelease = currentReleaseTmp
                        guard let currentReleaseName = currentRelease?.name else {
                            return
                        }
                        self.currentReleaseName = currentReleaseName
                        Log.debug("Found this release: \(currentReleaseName)")
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

                    guard
                        let currentReleaseTmp = currentRelease
                    else {
                        Log.debug("No current release available")
                        return
                    }

                    guard
                        let availableReleaseTmp = availableRelease
                    else {
                        Log.debug("No newer release available")
                        return
                    }

                    if availableReleaseTmp > currentReleaseTmp {
                        availableReleaseName = availableReleaseTmp.name
                        Log.info("Found availableRelease: \(availableReleaseName)")
                        _ = self.displayNewReleaseAvailableAlert()
                    }
                    else {
                        if isFromMenuCheck == false {
                            Log.debug("From startup check, not menu check, so not showing no newer release alert")
                        }
                        else{
                            NSAlert.createInfoAlert(title: NSLocalizedString("No Newer Release Available", comment: "No newer release available"),
                                                    message: NSLocalizedString("You are currently running the latest release.", comment: "You are currently running the latest release."))
                        }
                    }
                } catch {
                    Log.error("Error GitHub Exception: \(error.localizedDescription)")
                    NSAlert.createWarningAlert(title: NSLocalizedString("GitHub Request Failed", comment: "GitHub Request Failed"), message: error.localizedDescription)
                }

            case let .failure(error):
                Log.error("Error GitHub Failure: \(error.localizedDescription)")
                NSAlert.createWarningAlert(title: NSLocalizedString("GitHub Request Failed", comment: "GitHub Request Failed"), message: error.localizedDescription)
                if (manager?.isReachable == false) {
                    Log.error("manager?.isReachable == false")
                }
            }
        }
    }

    private func displayNewReleaseAvailableAlert() -> Bool {
        Log.debug("displayNewReleaseAvailableAlert")

        let prefs: UserDefaults = UserDefaults.standard
        var localURL: URL
        let message: String
        var asset: Asset?

        if isFromMenuCheck == false && prefs.string(forKey: SPSkipNewReleaseAvailable) == availableReleaseName {
            Log.debug("The user has opted out of more alerts regarding this version")
            return false
        }

        guard let mainWindow = NSApp.mainWindow else { return false }

        guard
            let availableReleaseURL = availableRelease?.htmlURL,
            let url = URL(string: availableReleaseURL)
        else {
            Log.error("release has no url")
            return false
        }

        localURL = url

        if let availableAsset = availableRelease?.assets.first(where: { $0.browserDownloadURL.count > 0 }) {
            asset = availableAsset
        }

        message = NSLocalizedString("Version %@ is available. You are currently running %@",
                                    comment: "Version %@ is available. You are currently running %@").format(availableReleaseName, currentReleaseName)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("A new version is available", comment: "A new version is available")
        alert.informativeText = message
        if isFromMenuCheck == false {
            alert.showsSuppressionButton = true
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "View").tag = GitHubReleaseManager.NSModalResponseView.rawValue

        if asset != nil {
            alert.addButton(withTitle: NSLocalizedString("Download", comment: "Download new version")).tag = GitHubReleaseManager.NSModalResponseDownload.rawValue
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button")).tag = NSApplication.ModalResponse.cancel.rawValue

        alert.beginSheetModal(for: mainWindow) { [self] (returnCode: NSApplication.ModalResponse) -> Void in
            self.Log.debug("returnCode: \(returnCode)")

            if let suppressionButton = alert.suppressionButton,
               suppressionButton.state == .on {
                prefs.setValue(self.availableReleaseName, forKey: SPSkipNewReleaseAvailable)
            }

            switch returnCode {
            case GitHubReleaseManager.NSModalResponseView:
                self.Log.debug("user clicked view")
                NSWorkspace.shared.open(localURL)
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

    private func downloadNewRelease(asset: Asset) {
        Log.debug("downloadNewRelease")

        Log.debug("asset.browserDownloadURL: \(asset.browserDownloadURL)")

        guard let mainWindow = NSApp.mainWindow else { return }

        let downloadNSString: NSString = asset.browserDownloadURL as NSString

        let size : Double = Double(asset.size)
        let sizeStr : String = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

        Log.debug("asset.file: \(downloadNSString.lastPathComponent)")

        // init progress view
        let progressWindowControllerStoryboard = NSStoryboard.init(name: NSStoryboard.Name("ProgressWindowController"), bundle: nil)

        if #available(OSX 10.15, *) {
            progressWindowController = progressWindowControllerStoryboard.instantiateInitialController()
        }
        else {
            // Fallback on earlier versions
            guard let tmpPWC = progressWindowControllerStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ProgressWindowController")) as? ProgressWindowController else {
                return
            }
            progressWindowController = tmpPWC
        }

        guard let tmpPVC = progressWindowController?.contentViewController as? ProgressViewController else {
            return
        }

        progressViewController = tmpPVC

        let message = NSLocalizedString("Downloading Sequel Ace - %@",
                                        comment: "Downloading Sequel Ace - %@").format(availableReleaseName)

        progressViewController?.theTitle.cell?.title = message
        progressViewController?.subtitle.cell?.title = NSLocalizedString("Calculating time remaining...", comment: "Calculating time remaining")

        progressWindowController?.window?.title = NSLocalizedString("Download Progress", comment: "Download Progress")
        progressViewController?.view .displayIfNeeded()
        progressWindowController?.window? .displayIfNeeded()
        
        // reposition within the main window
        let panelRect: NSRect = progressWindowController?.window?.frame ?? NSMakeRect(0, 0, 0, 0)
        let screenRect: NSRect = mainWindow.convertToScreen(panelRect)
        progressWindowController?.window?.setFrame(screenRect, display: true)

        progressWindowController?.showWindow(mainWindow)

        let destination: DownloadRequest.Destination = { _, _ in
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let fileURL = downloadsURL.appendingPathComponent(downloadNSString.lastPathComponent)
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        var previousFractionCompleted: Double = 0.0
        var secondsLeft: Double = 0.0
        var previousSecondsLeft: Double = 0.0
        var percentLeft: Double = 0.0
        var ETA: Double = 0.0
        var diff: Double = 0.0
        var dlBytes : Double = 0.0
        var dlBytesStr : String = ""

        let ti: UInt64 = GitHubReleaseManager._monotonicTime()

        download = AF.download(asset.browserDownloadURL, to: destination)
            .downloadProgress { [self] progress in
                progressViewController?.progressIndicator.startAnimation(nil)
                Log.debug("Download Progress: \(progress.fractionCompleted)")
                previousFractionCompleted = progress.fractionCompleted - previousFractionCompleted
                Log.debug("previousFractionCompleted: \(previousFractionCompleted)")
                diff = GitHubReleaseManager._timeIntervalSinceMonotonicTime(comparisonTime: ti)
                Log.debug("diff: \(diff)")

                dlBytes = progress.fractionCompleted * size

                dlBytesStr = ByteCountFormatter.string(fromByteCount: Int64(dlBytes), countStyle: .file)

                progressViewController?.bytes.cell?.title = String.localizedStringWithFormat("%@ of %@", dlBytesStr, sizeStr)

                Log.debug("Download Progress Bytes: \(dlBytes)")
                Log.debug("Download Progress dlBytesStr: \(dlBytesStr)")

                percentLeft = (1 - progress.fractionCompleted) + 1
                Log.debug("percentLeft: \(percentLeft)")

                ETA = diff * percentLeft

                secondsLeft = ETA - diff

                if secondsLeft < previousSecondsLeft {
                    Log.debug("Going down now")
                    progressViewController?.subtitle.cell?.title = String.localizedStringWithFormat("About %.1f seconds left", secondsLeft)
                }

                Log.debug("previousSecondsLeft: \(previousSecondsLeft)")

                previousSecondsLeft = secondsLeft

                Log.debug("ETA: \(ETA)")
                Log.debug("secondsLeft: \(secondsLeft)")

                progressViewController?.progressIndicator.increment(by: previousFractionCompleted)

                previousFractionCompleted = progress.fractionCompleted
                if progress.fractionCompleted == 1.0 {
                    progressViewController?.progressIndicator.doubleValue = 1.0
                    progressViewController?.progressIndicator.stopAnimation(nil)
                    Log.debug("Download Complete")
                }
            }
            .validate() // check response code etc
            .response { [self] response in

                progressViewController?.progressIndicator.stopAnimation(nil)
                progressWindowController?.close()

                switch response.result {
                case .success:
                    Log.debug("Validation Successful")
                    Log.debug("diff: \(GitHubReleaseManager._timeIntervalSinceMonotonicTime(comparisonTime: ti))")
                    if response.error == nil, let filePath = response.fileURL?.path {
                        Log.debug("downloadNewRelease: \(filePath)")
                        let downloadDir: String = (filePath as NSString).deletingLastPathComponent
                        Log.debug("downloadDir: \(downloadDir)")
                        NSWorkspace.shared.openFile(downloadDir, withApplication: "Finder")
                    }

                case let .failure(error):
                    // only show alert if the user did not explicitly cancel the download
                    if error.isExplicitlyCancelledError == false {
                        Log.error("Error: \(error.localizedDescription)")
                        NSAlert.createWarningAlert(title: NSLocalizedString("Download Failed", comment: "Download Failed"), message: error.localizedDescription)
                        if (manager?.isReachable == false) {
                            Log.error("manager?.isReachable == false")
                        }
                    }
                }
            }
    }

    // MARK: Timing functions

    private static func _monotonicTime() -> UInt64 {
        return clock_gettime_nsec_np(CLOCK_MONOTONIC)
    }

    private static func _timeIntervalSinceMonotonicTime(comparisonTime: UInt64) -> Double {
        return Double(_monotonicTime() - comparisonTime) * 1e-9
    }

    // MARK: ProgressViewControllerDelegate
    func cancelPressed() {
        Log.debug("cancelPressed, cancelling download")
        download?.cancel()
        progressViewController?.progressIndicator.stopAnimation(nil)
        progressWindowController?.close()
    }

    func closePressed() {
        Log.debug("closePressed, cancelling download")
        download?.cancel()
        progressViewController?.progressIndicator.stopAnimation(nil)
    }
}
