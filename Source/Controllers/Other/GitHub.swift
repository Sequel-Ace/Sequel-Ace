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

struct SAGitHubReleaseTagIdentity {
    let channel: String
    let version: String
    let build: Int

    init?(_ value: String) {
        let channelAndValue = value.split(separator: "/", omittingEmptySubsequences: false)
        guard
            channelAndValue.count == 2,
            channelAndValue[0] == "production" || channelAndValue[0] == "beta",
            let buildSeparator = channelAndValue[1].lastIndex(of: "-"),
            buildSeparator != channelAndValue[1].startIndex,
            let build = Int(channelAndValue[1][channelAndValue[1].index(after: buildSeparator)...]),
            build > 0
        else {
            return nil
        }

        channel = String(channelAndValue[0])
        version = String(channelAndValue[1][..<buildSeparator])
        self.build = build
    }
}

/// The subset of a GitHub release that the in-app update check uses.
///
/// GitHub adds fields over time and release authors may be users, bots, or
/// GitHub Apps. Decoding only the values used by the update flow keeps those
/// unrelated API details from invalidating the entire releases response.
struct SAGitHubRelease: Decodable, Comparable {
    private static let canonicalBetaArtifactNamingMinimumBuild = 20_110
    static let settlingInterval: TimeInterval = 15 * 60

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
        // Missing release-state gates must never make a partial response look public.
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? true
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? true
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
            ?? container.decode(Date.self, forKey: .createdAt)
        assets = try container.decodeIfPresent([SAGitHubReleaseAsset].self, forKey: .assets) ?? []
    }

    static func decodeList(from data: Data) throws -> [SAGitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SAGitHubRelease].self, from: data)
    }

    func matchesInstalledBuild(named installedBuildName: String, releaseTag: String? = nil) -> Bool {
        if let releaseTag {
            return tagName == releaseTag
        }

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

        if usesCanonicalBetaArtifactNaming {
            return canonicalBetaAsset(for: variant, in: appZips)
        }

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

    private var usesCanonicalBetaArtifactNaming: Bool {
        guard let tagIdentity else {
            return false
        }

        // Builds before the guarded release workflow used less predictable beta ZIP names.
        return tagIdentity.channel == "beta" && tagIdentity.build >= Self.canonicalBetaArtifactNamingMinimumBuild
    }

    private func canonicalBetaAsset(
        for variant: SAGitHubReleaseAppVariant,
        in appZips: [SAGitHubReleaseAsset]
    ) -> SAGitHubReleaseAsset? {
        guard let tagIdentity, tagIdentity.channel == "beta" else {
            return nil
        }

        let prefix = "Sequel-Ace-\(tagIdentity.version)-beta"
        let suffix = variant == .beta ? "-alpha.zip" : ".zip"
        return Self.onlyAsset(in: appZips.filter { asset in
            guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(suffix) else {
                return false
            }

            let iterationStart = asset.name.index(asset.name.startIndex, offsetBy: prefix.count)
            let iterationEnd = asset.name.index(asset.name.endIndex, offsetBy: -suffix.count)
            return iterationStart < iterationEnd
                && Int(asset.name[iterationStart..<iterationEnd]).map { $0 > 0 } == true
        })
    }

    func settlingTimeRemaining(at date: Date) -> TimeInterval? {
        let latestAssetChange = assets.compactMap(\.lastModifiedAt).max()
        let latestReleaseChange = latestAssetChange.map { max(publishedAt, $0) } ?? publishedAt
        let remaining = Self.settlingInterval - date.timeIntervalSince(latestReleaseChange)
        return remaining > 0 ? remaining : nil
    }

    func isSettled(at date: Date) -> Bool {
        settlingTimeRemaining(at: date) == nil
    }

    private var tagIdentity: SAGitHubReleaseTagIdentity? {
        SAGitHubReleaseTagIdentity(tagName)
    }
}

enum SAGitHubReleaseSettlingPolicy {
    static func retryDelay(
        at date: Date,
        currentRelease: SAGitHubRelease?,
        candidateReleases: [SAGitHubRelease]
    ) -> TimeInterval? {
        guard
            let currentRelease,
            let newestRelease = candidateReleases.max(),
            newestRelease > currentRelease
        else {
            return nil
        }

        return newestRelease.settlingTimeRemaining(at: date)
    }
}

enum SAGitHubReleasePagination {
    static let pageSize = 100

    static func nextPageURL(
        from linkHeader: String?,
        releases: [SAGitHubRelease],
        installedBuildName: String,
        installedReleaseTag: String?
    ) -> URL? {
        guard
            releases.contains(where: {
                $0.matchesInstalledBuild(named: installedBuildName, releaseTag: installedReleaseTag)
            }) == false,
            let linkHeader
        else {
            return nil
        }

        for link in linkHeader.split(separator: ",") {
            let components = link.split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard
                components.dropFirst().contains("rel=\"next\""),
                let value = components.first,
                value.hasPrefix("<"),
                value.hasSuffix(">"),
                let url = URL(string: String(value.dropFirst().dropLast())),
                url.scheme == "https",
                url.host == "api.github.com"
            else {
                continue
            }

            return url
        }

        return nil
    }
}

struct SAGitHubReleaseAsset: Decodable {
    let name: String
    let size: Int
    let browserDownloadURL: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        browserDownloadURL = try container.decodeIfPresent(String.self, forKey: .browserDownloadURL) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
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

    fileprivate var lastModifiedAt: Date? {
        updatedAt ?? createdAt
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
