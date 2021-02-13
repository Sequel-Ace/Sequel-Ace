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
import Ink

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
                        let json = try JSONSerialization.jsonObject(with: response.data!, options: JSONSerialization.ReadingOptions()) // FIXME: data!
                        let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                        let gitHub = try GitHub(data: prettyData)

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
                            Log.debug("Found release at index:[\(i)] name: \(currentReleaseName))")
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

        message = "Version %@ is available. You are currently running %@" .format(availableReleaseName, currentReleaseName)

        let alert = NSAlert()
        alert.messageText = "A new version is available"
        alert.informativeText = message
        alert.showsSuppressionButton = true
        alert.alertStyle = .informational
        alert.addButton(withTitle: "View").tag = GitHubReleaseManager.NSModalResponseView.rawValue
        
        if asset != nil {
            alert.addButton(withTitle: "Download").tag = GitHubReleaseManager.NSModalResponseDownload.rawValue
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
                    self.downloadNewRelease(asset: asset!)
                case NSApplication.ModalResponse.cancel:
                    self.Log.debug("user clicked cancel")
                    self.generateReleaseNoteFromRelease(fromRelease: currentRelease!, toRelease: availableRelease!)
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

        guard let mainWindow = NSApp.mainWindow else { return }

        let progressbar = NSProgressIndicator()
        progressbar.frame = NSRect(x: 100, y: 200, width: 150, height: 100)
        progressbar.minValue = 0.0
        progressbar.maxValue = 1.0
        progressbar.isIndeterminate = false
        progressbar.isDisplayedWhenStopped = false

        mainWindow.contentView?.addSubview(progressbar)
        progressbar.startAnimation(self)
                    
        var previousFractionCompleted : Double = 0.0

        AF.download(asset.browserDownloadURL, to: destination)
            .downloadProgress { progress in
                self.Log.debug("Download Progress: \(progress.fractionCompleted)")
                previousFractionCompleted = progress.fractionCompleted - previousFractionCompleted
                self.Log.debug("previousFractionCompleted: \(previousFractionCompleted)")
                progressbar.increment(by: previousFractionCompleted)
                previousFractionCompleted = progress.fractionCompleted
                if progress.fractionCompleted == 1.0 {
                    self.Log.debug("Download Complete")
                    progressbar.stopAnimation(self)
                    progressbar.removeFromSuperview()
                }
            }.response { response in
                debugPrint(response)

                if response.error == nil, let filePath = response.fileURL?.path {
                    self.Log.debug("downloadNewRelease: \(filePath)")
                }
            }
    }

    private func generateReleaseNoteFromRelease(fromRelease: GitHubElement, toRelease: GitHubElement ){

        guard
            var fromIndex : Int = releases.firstIndex(of: fromRelease),
            fromIndex != NSNotFound
        else {
            Log.error("Release not found: \(fromRelease)")
            return
        }

        guard
            var toIndex : Int = releases.firstIndex(of: toRelease),
            toIndex != NSNotFound
        else {
            Log.error("Release not found: \(toRelease)")
            return
        }

        self.Log.debug("toIndex: \(toIndex)")
        self.Log.debug("fromIndex: \(fromIndex)")

        if fromIndex < toIndex {
            self.Log.debug("reversing release array")

            let tmp = fromIndex
            fromIndex = toIndex
            toIndex = tmp
            releases.reverse()
        }


        self.Log.debug("toIndex: \(toIndex)")
        self.Log.debug("fromIndex: \(fromIndex)")

        var matchedIndices: [Int] = []
        for (i, _) in zip(releases.indices, releases) {
            self.Log.debug("i: \(i)")

            if i <= fromIndex && i >= toIndex{
                matchedIndices.append(i)
            }
        }

        self.Log.debug("matchedIndices: \(matchedIndices)")

        let result = NSMutableAttributedString()
        let newLine = NSAttributedString(string: "\n")

        result.beginEditing()

        for (_, value) in matchedIndices.enumerated() {

            self.Log.debug("value: \(value)")
            self.Log.debug("GitHubElement: \(releases[value].name)")

            if result.length > 0 {
                result.append(newLine)
                result.append(newLine)
            }

            result.append(NSAttributedString(string: "## " + releases[value].name, attributes: nil))
            result.append(newLine)
            result.append(newLine)
            let lines = releases[value].body.separatedIntoLines()

            Log.debug("lines: [\(lines)]")

            var newLinesArray : [String] = []
            do{
                for str in lines {
                    var newStr = str.trimmedString
                    if newStr.count == 0 {
                        continue
                    }
                    if newStr.hasPrefix("###") {
                        newStr.append("\n")
                        newStr.insert("\n", at: newStr.startIndex)
                    }

                    let searchText = newStr
                    let regex = try NSRegularExpression(pattern: "(-\\s)(\\w*)(.*)", options: [])
                    let replacedText = regex.stringByReplacingMatches(in: searchText, options: [], range: NSRange(searchText.startIndex..<searchText.endIndex, in: searchText), withTemplate: "$1`$2`$3")

                    self.Log.debug("replacedText: \(replacedText)")

                    newLinesArray.append(replacedText)
                }
            }
            catch{

            }

            self.Log.debug("newLinesArray: \(newLinesArray)")


            let newLinesNSArray = newLinesArray as NSArray


            let newStr = newLinesNSArray.componentsJoined(by: "\n")
            self.Log.debug("newStr: \(newStr)")

            result.append(NSAttributedString(string: newStr, attributes: nil))


        }

        result.endEditing()
        self.Log.debug("result: \(result)")

        let markdown: String = result.mutableString as String
        let parser = MarkdownParser()
        let html = parser.html(from: markdown)

        self.Log.debug("html: \(html)")



    }
}
