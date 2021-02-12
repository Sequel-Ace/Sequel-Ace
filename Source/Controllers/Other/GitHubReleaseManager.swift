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
            fatalError("Error - you must call setup before accessing GitHubReleaseManager.sharedInstance")
        }

        //Regular initialisation using config

        self.user              = config.user
        self.project           = config.project
        self.includeDraft      = config.includeDraft
        self.includePrerelease = config.includePrerelease
        let urlStr             = GitHubReleaseManager.githubURLStr.format(user, project)

        Log.info("GitHubReleaseManager.config = \(String(describing: GitHubReleaseManager.config))")
        Log.info("urlStr = \(urlStr)")

        super.init()

        AF.request(urlStr){ urlRequest in
            urlRequest.timeoutInterval = 60
//            urlRequest.addValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            debugPrint(urlRequest)
        }
        .validate() // check response code etc
        .responseJSON { [self] response in
            switch response.result {
                case .success:
                    print("Validation Successful")
//                    debugPrint(response)
//                    let stringNS2 = String(decoding: response.data!, as: UTF8.self)
//                    let string2 = stringNS2.replacingOccurrences(of: "\\", with: "", options: .literal, range: nil)

                    do{
                        let json = try JSONSerialization.jsonObject(with: response.data!, options: JSONSerialization.ReadingOptions())
                        let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
//                        let prettyString = String(data: prettyData, encoding: String.Encoding.utf8)
                        let gitHub = try GitHub(data: prettyData)
//                        debugPrint(prettyString as Any)

//                        for element in gitHub {
//                            let str = try element.jsonString()
//                            debugPrint(str as Any)
//                        }

                        let releasesArray = gitHub.sorted(by: { (element0: GitHubElement, element1: GitHubElement) -> Bool in
                            return element0 > element1
                        })

                        debugPrint(releasesArray)
//
                        if let i = releasesArray.firstIndex(where: { $0.name == "3.1.0 (3012)" }) {
                            print("\(releasesArray[i]) 3.1.0 (3012)")
                            currentRelease = releasesArray[i]
                        }

                        releases = releasesArray
                        availableRelease = releases.first

                        debugPrint(availableRelease as Any)

                        
                    }
                    catch{
                        print(error)
                    }
//                    let stringNS = NSData(data: response.data!)
//                    let str : NSString = stringNS2.bv_jsonString(withPrettyPrint: true)! as NSString
//                    let string2 = str.replacingOccurrences(of: "\\", with: "")
//                    let gitHub = GitHub(response)
//                    debugPrint(string2)

                case let .failure(error):
                    print(error)
            }

        }
        .responseString{ response in
            debugPrint("Response: \(response)")

        }

    }

    /*

     @property (nonatomic, readonly) NSURL* url;
     @property (nonatomic, readonly) NSString* user;
     @property (nonatomic, readonly) NSString* project;

     @property (nonatomic, readonly) MLGitHubRelease* currentRelease;
     @property (nonatomic, readonly) MLGitHubRelease* availableRelease;
     @property (nonatomic, readonly) MLGitHubReleases* releases;

     @property (nonatomic, assign) BOOL includeDraft;
     @property (nonatomic, assign) BOOL includePrerelease;

     @property (nonatomic, weak) id<MLGitHubReleaseCheckerDelegate> delegate;
     summarize(toLength length: Int, withEllipsis ellipsis: Bool) -
     */


}
