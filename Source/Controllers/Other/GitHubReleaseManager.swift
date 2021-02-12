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
    @objc static let sharedInstance                     = GitHubReleaseManager()
    static let githubURLStr           : String          = "https://api.github.com/repos/%@/%@/releases"
    private var user                  : String
    private var project               : String
    private var includeDraft          : Bool
    private var includePrerelease     : Bool
    private var currentRelease        : GitHubElement?
    private var availableRelease      : GitHubElement?
    private var releases              : [GitHubElement] = []
    private let prefs                 : UserDefaults    = UserDefaults.standard
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
                        let json = try JSONSerialization.jsonObject(with: response.data!, options: JSONSerialization.ReadingOptions())
                        let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                        let gitHub = try GitHub(data: prettyData)

                        var releasesArray = gitHub.sorted(by: { (element0: GitHubElement, element1: GitHubElement) -> Bool in
                            return element0 > element1
                        })

                        Log.debug("releasesArray count: \(releasesArray.count)")

                        if let i = releasesArray.firstIndex(where: { $0.name == name }) {
                            currentRelease = releasesArray[i]
                            Log.debug("Found release at index:[\(i)] name: \(String(describing: currentRelease?.name))")
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
                            Log.info("Found availableRelease: \(String(describing: availableRelease?.name))")
                            NotificationCenter.default.post(name: Notification.Name(NSNotification.Name.SPNewReleaseAvailable.rawValue), object: availableRelease)
                            self.displayNewReleaseAvailableAlert()
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

    private func displayNewReleaseAvailableAlert(){

        Log.debug("displayNewReleaseAvailableAlert")

        var localURL : String
        if prefs.string(forKey: SPSkipNewReleaseAvailable) == availableRelease?.name {
            Log.debug("The user has opted out of more alerts regarding this version")
            return
        }

        if (availableRelease?.htmlURL == nil) {
            Log.error("release has no url")
            return;
        }
        else{
            localURL = availableRelease?.htmlURL ?? ""
        }

        let message = "Version %@ is available. You are currently running %@".format(availableRelease!.name, currentRelease!.name)

        NSAlert .createDefaultAlertWithSuppression(title: "A new version is available",
                                                   message: message,
                                                   suppressionKey:SPSkipNewReleaseAvailable,
                                                   suppressionValue:availableRelease?.name,
                                                   primaryButtonTitle: "View",
                                                   primaryButtonHandler: {
                                                    self.Log.debug("user clicked view")
                                                    NSWorkspace.shared.open(availableRelease!.htmlURL)
                                                   })

        /*
         [NSAlert createDefaultAlertWithSuppressionWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Double Check", @"Double Check")] message:@"Double checking as you have 'Show warning before executing a query' set in Preferences" suppressionKey:SPQueryWarningEnabledSuppressed suppressionValue:nil primaryButtonTitle:NSLocalizedString(@"Proceed", @"Proceed") primaryButtonHandler:^{
             SPLog(@"User clicked Yes, exec queries");
             retCode = YES;
         } cancelButtonHandler:^{
             SPLog(@"Cancel pressed");
             self->isEditingRow = NO;
             self->currentlyEditingRow = -1;
             // reload
             [self loadTableValues];
             retCode = NO;
         }];

         */

    }
}
