//
//  GitHub.swift
//  Sequel Ace
//
//  Created by James on 13/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

enum SAGitHubReleaseAppVariant {
    case production
    case beta
}

/// The subset of a GitHub release that the in-app update check uses.
///
/// GitHub adds fields over time and release authors may be users, bots, or
/// GitHub Apps. Decoding only the values used by the update flow keeps those
/// unrelated API details from invalidating the entire releases response.
struct SAGitHubRelease: Decodable, Comparable {
    let tagName: String
    let name: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date
    let assets: [SAGitHubReleaseAsset]

    static func < (lhs: SAGitHubRelease, rhs: SAGitHubRelease) -> Bool {
        lhs.publishedAt < rhs.publishedAt
    }

    static func == (lhs: SAGitHubRelease, rhs: SAGitHubRelease) -> Bool {
        lhs.publishedAt == rhs.publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? tagName
        htmlURL = try container.decode(String.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
            ?? container.decode(Date.self, forKey: .createdAt)
        assets = try container.decodeIfPresent([SAGitHubReleaseAsset].self, forKey: .assets) ?? []
    }

    static func decodeList(from data: Data) throws -> [SAGitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SAGitHubRelease].self, from: data)
    }

    func matchesInstalledBuild(named installedBuildName: String) -> Bool {
        if name == installedBuildName || name.hasPrefix("\(installedBuildName) ") {
            return true
        }

        let tagBuildName = installedBuildName
            .replacingOccurrences(of: " (", with: "-")
            .replacingOccurrences(of: ")", with: "")
        return tagName.split(separator: "/").last.map(String.init) == tagBuildName
    }

    func compatibleAppZip(for variant: SAGitHubReleaseAppVariant) -> SAGitHubReleaseAsset? {
        let appZips = assets.filter(\.isAppZip)

        guard appZips.count > 1 else {
            return inferredAppVariant == variant ? appZips.first : nil
        }

        let alphaAppZips = appZips.filter(\.isAlphaAppZip)
        if alphaAppZips.isNotEmpty {
            // Canonical beta releases suffix the beta-bundle artifact with "-alpha".
            let matchingAppZips = variant == .beta ? alphaAppZips : appZips.filter { !$0.isAlphaAppZip }
            return Self.onlyAsset(in: matchingAppZips)
        }

        let betaAppZips = appZips.filter(\.isBetaNamedAppZip)
        let productionAppZips = appZips.filter { !$0.isBetaNamedAppZip }
        guard betaAppZips.isNotEmpty, productionAppZips.isNotEmpty else {
            return nil
        }

        return Self.onlyAsset(in: variant == .beta ? betaAppZips : productionAppZips)
    }

    private var inferredAppVariant: SAGitHubReleaseAppVariant {
        switch tagName.split(separator: "/").first {
        case "beta":
            return .beta
        case "production":
            return .production
        default:
            return prerelease ? .beta : .production
        }
    }

    private static func onlyAsset(in assets: [SAGitHubReleaseAsset]) -> SAGitHubReleaseAsset? {
        assets.count == 1 ? assets[0] : nil
    }
}

struct SAGitHubReleaseAsset: Decodable {
    let name: String
    let size: Int
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        browserDownloadURL = try container.decodeIfPresent(String.self, forKey: .browserDownloadURL) ?? ""
    }

    fileprivate var isAppZip: Bool {
        let normalizedName = name.lowercased()
        let hasAppPrefix = normalizedName.hasPrefix("sequel-ace-") || normalizedName.hasPrefix("sequelace-")
        return hasAppPrefix && normalizedName.hasSuffix(".zip") && size > 0 && browserDownloadURL.isNotEmpty
    }

    fileprivate var isAlphaAppZip: Bool {
        name.lowercased().dropLast(4).contains("-alpha")
    }

    fileprivate var isBetaNamedAppZip: Bool {
        name.lowercased().dropLast(4).contains("-beta")
    }
}

/// Decides whether an update-check failure should interrupt the user.
enum SAGitHubReleaseErrorPolicy {
    static func shouldPresentError(isUserInitiated: Bool, statusCode: Int?, underlyingError: Error?) -> Bool {
        guard isUserInitiated else {
            return false
        }

        if let statusCode,
           ephemeralHTTPStatusCodes.contains(statusCode) || (500...599).contains(statusCode) {
            return false
        }

        if let underlyingError {
            let urlError = underlyingError as NSError
            if urlError.domain == NSURLErrorDomain,
               ephemeralURLErrorCodes.contains(URLError.Code(rawValue: urlError.code)) {
                return false
            }
        }

        return true
    }

    private static let ephemeralURLErrorCodes: Set<URLError.Code> = [
        .cancelled,
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .resourceUnavailable,
        .notConnectedToInternet,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed,
        .cannotLoadFromNetwork
    ]

    private static let ephemeralHTTPStatusCodes: Set<Int> = [403, 408, 425, 429]
}
