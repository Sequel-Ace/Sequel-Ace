//
//  GitHub.swift
//  Sequel Ace
//
//  Created by James on 13/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

/// Identifies App Store and TestFlight installs without reading receipt contents.
enum SAAppStoreReceiptPolicy {
    static func isAppStoreInstall(
        receiptURL: URL?,
        receiptExists: (URL) -> Bool
    ) -> Bool {
        guard let receiptURL else {
            return false
        }

        return receiptExists(receiptURL)
    }
}

/// A private build — a personally signed build of a fork, stamped at packaging time — carries
/// `SAPrivateBuild = YES` in its Info.plist. It is not an upstream release, so like an App Store install it
/// never uses the upstream GitHub updater: no "Check for Updates…" item and no automatic check.
enum SAPrivateBuildPolicy {
    /// Keep in sync with the packaging step that stamps it.
    static let infoPlistKey = "SAPrivateBuild"

    static func isPrivateBuild(infoDictionary: [String: Any]?) -> Bool {
        switch infoDictionary?[infoPlistKey] {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            return ["yes", "true", "1"].contains(text.lowercased())
        default:
            return false
        }
    }

    static func offersGitHubUpdates(isAppStoreInstall: Bool, isPrivateBuild: Bool) -> Bool {
        !isAppStoreInstall && !isPrivateBuild
    }

    /// The "App Sandbox Issue" alerts for stale or missing secure bookmarks (at launch, and in Settings ▸ Network's
    /// known-hosts check). A private build is unsandboxed and reads files without bookmarks, so it never shows them.
    static func showsStaleBookmarkAlert(isPrivateBuild: Bool, staleBookmarkCount: Int) -> Bool {
        !isPrivateBuild && staleBookmarkCount > 0
    }

    /// Stale bookmarks hold back the launch auto-connect only where they matter: in the sandboxed build.
    static func staleBookmarksAllowAutoConnect(isPrivateBuild: Bool, staleBookmarkCount: Int) -> Bool {
        isPrivateBuild || staleBookmarkCount == 0
    }

    /// Settings ▸ Files marks stale bookmarks (red entries, the stale hint, the re-select panel) only in the sandboxed
    /// build: an unsandboxed private build doesn't need security-scoped bookmarks — it opens the files without them (its
    /// stale entries are typically bookmarks minted for a differently signed, sandboxed app). The stored bookmarks are
    /// left as they are.
    static func marksStaleBookmarks(isPrivateBuild: Bool, staleBookmarkCount: Int) -> Bool {
        !isPrivateBuild && staleBookmarkCount > 0
    }

    /// Whether ~/.aws is reached through a security-scoped bookmark the user grants ("Authorize Access to ~/.aws…",
    /// the write-access re-grant for console sign-in). The sandboxed build needs one; an unsandboxed private build
    /// reads ~/.aws directly, with no authorization step.
    static func usesAWSDirectoryBookmark(isPrivateBuild: Bool) -> Bool {
        !isPrivateBuild
    }

    /// Whether AWS IAM favourites can save, test, connect and list profiles now, the one decision every AWS directory
    /// gate goes through (`AWSDirectoryBookmarkManager.directoryAccess`).
    /// - Parameters:
    ///   - sandboxedAccess: the sandboxed build's check (a bookmark that resolves, or a directly readable
    ///     credentials file); not consulted in a private build.
    ///   - awsFilesExist: a private build's check: ~/.aws, or the credentials / config file, exists.
    static func awsDirectoryAccess(isPrivateBuild: Bool, sandboxedAccess: () -> Bool, awsFilesExist: () -> Bool) -> SAAWSDirectoryAccess {
        if usesAWSDirectoryBookmark(isPrivateBuild: isPrivateBuild) {
            return sandboxedAccess() ? .available : .needsAuthorization
        }
        return awsFilesExist() ? .available : .missing
    }
}

/// How AWS IAM favourites reach ~/.aws (`SAPrivateBuildPolicy.awsDirectoryAccess`).
@objc enum SAAWSDirectoryAccess: Int {
    /// Profiles can be read: through the bookmark (sandboxed) or directly (private build).
    case available
    /// Sandboxed build without a working bookmark: the user must authorize ~/.aws first (saving, testing and
    /// connecting are refused until then).
    case needsAuthorization
    /// Private build without ~/.aws (nor the credentials / config file): nothing to authorize, no profiles to list;
    /// saving is allowed, connecting reports the missing profile.
    case missing
}

/// Prevents App Store builds and opted-out background checks from using the GitHub updater.
@objc final class SAGitHubReleaseCheckPolicy: NSObject {
    @objc(shouldCheckWithIsUserInitiated:automaticChecksEnabled:isAppStoreInstall:)
    static func shouldCheck(
        isUserInitiated: Bool,
        automaticChecksEnabled: Bool,
        isAppStoreInstall: Bool
    ) -> Bool {
        !isAppStoreInstall && (isUserInitiated || automaticChecksEnabled)
    }
}

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
            Self.isASCIIDigits(channelAndValue[1][channelAndValue[1].index(after: buildSeparator)...]),
            channelAndValue[1][channelAndValue[1].index(after: buildSeparator)] != "0",
            let build = Int(channelAndValue[1][channelAndValue[1].index(after: buildSeparator)...]),
            build > 0
        else {
            return nil
        }

        let versionValue = channelAndValue[1][..<buildSeparator]
        let versionComponents = versionValue.split(separator: ".", omittingEmptySubsequences: false)
        guard versionComponents.count == 3, versionComponents.allSatisfy(Self.isASCIIDigits) else {
            return nil
        }

        channel = String(channelAndValue[0])
        version = String(versionValue)
        self.build = build
    }

    private static func isASCIIDigits<T: StringProtocol>(_ value: T) -> Bool {
        value.isNotEmpty && value.allSatisfy { $0 >= "0" && $0 <= "9" }
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
        if lhs.publishedAt != rhs.publishedAt {
            return lhs.publishedAt < rhs.publishedAt
        }

        if
            let lhsIdentity = lhs.tagIdentity,
            let rhsIdentity = rhs.tagIdentity,
            lhsIdentity.channel == rhsIdentity.channel,
            lhsIdentity.build != rhsIdentity.build
        {
            return lhsIdentity.build < rhsIdentity.build
        }

        return lhs.tagName < rhs.tagName
    }

    static func == (lhs: SAGitHubRelease, rhs: SAGitHubRelease) -> Bool {
        lhs.publishedAt == rhs.publishedAt && lhs.tagName == rhs.tagName
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

        if usesReleaseChannelTag && tagIdentity == nil {
            return nil
        }

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

    private var usesReleaseChannelTag: Bool {
        let channel = tagName.split(separator: "/", omittingEmptySubsequences: false).first
        return channel == "production" || channel == "beta"
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
        // Each installed variant needs only its own artifact; the shared settle
        // window keeps an in-progress upload from reaching either updater.
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
        let remaining = Self.settlingInterval - date.timeIntervalSince(latestReleaseChange)
        return remaining > 0 ? remaining : nil
    }

    func isSettled(at date: Date) -> Bool {
        settlingTimeRemaining(at: date) == nil
    }

    private var tagIdentity: SAGitHubReleaseTagIdentity? {
        SAGitHubReleaseTagIdentity(tagName)
    }

    var phasedRolloutStartedAt: Date {
        latestReleaseChange.addingTimeInterval(Self.settlingInterval)
    }

    private var latestReleaseChange: Date {
        let latestAssetChange = assets.compactMap(\.lastModifiedAt).max()
        return latestAssetChange.map { max(publishedAt, $0) } ?? publishedAt
    }
}

/// Mirrors Apple's seven-day phased-release percentages for automatic GitHub update prompts.
/// Manual checks remain available immediately after the release's artifact-settling window.
enum SAGitHubReleaseRolloutPolicy {
    static let installationSeedPreferenceKey = "SAGitHubReleaseRolloutSeed"

    private static let day: TimeInterval = 24 * 60 * 60
    private static let dailyPercentages = [1, 2, 5, 10, 20, 50, 100]
    private static let cohortBucketCount = 10_000

    static func rolloutPercentage(at date: Date, startedAt: Date) -> Int {
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0 else {
            return 0
        }

        let dayIndex = min(Int(elapsed / day), dailyPercentages.count - 1)
        return dailyPercentages[dayIndex]
    }

    static func shouldOffer(
        releaseTag: String,
        rolloutStartedAt: Date,
        at date: Date,
        installationSeed: String?,
        isUserInitiated: Bool
    ) -> Bool {
        if isUserInitiated {
            return true
        }

        let percentage = rolloutPercentage(at: date, startedAt: rolloutStartedAt)
        guard percentage > 0 else {
            return false
        }
        guard percentage < 100 else {
            return true
        }
        guard let installationSeed else {
            return false
        }

        return cohortBucket(installationSeed: installationSeed, releaseTag: releaseTag)
            < percentage * (cohortBucketCount / 100)
    }

    /// Treats the newest compatible release as the rollout gate. Falling back
    /// to an older, fully rolled-out release would offer an obsolete
    /// intermediate update while the intended update is still phased.
    static func newestOfferedRelease(
        in releases: [SAGitHubRelease],
        at date: Date,
        installationSeed: String?,
        isUserInitiated: Bool
    ) -> SAGitHubRelease? {
        guard let newestRelease = releases.max() else {
            return nil
        }

        return shouldOffer(
            releaseTag: newestRelease.tagName,
            rolloutStartedAt: newestRelease.phasedRolloutStartedAt,
            at: date,
            installationSeed: installationSeed,
            isUserInitiated: isUserInitiated
        ) ? newestRelease : nil
    }

    static func installationSeed(in defaults: UserDefaults) -> String {
        if
            let storedSeed = defaults.string(forKey: installationSeedPreferenceKey),
            UUID(uuidString: storedSeed) != nil
        {
            return storedSeed
        }

        let seed = UUID().uuidString
        defaults.set(seed, forKey: installationSeedPreferenceKey)
        return seed
    }

    static func cohortBucket(installationSeed: String, releaseTag: String) -> Int {
        // Swift's Hasher is intentionally randomized per process. FNV-1a keeps a
        // given installation in a stable, release-specific cohort across launches.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in installationSeed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        hash = (hash ^ 0) &* 1_099_511_628_211
        for byte in releaseTag.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(hash % UInt64(cohortBucketCount))
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

    /// Builds a settling retry that preserves the initiating check's authorization.
    static func retryOperation(
        installedBuildName: String,
        installedReleaseTag: String?,
        isUserInitiated: Bool,
        perform: @escaping (String, String?, Bool) -> Void
    ) -> () -> Void {
        {
            perform(installedBuildName, installedReleaseTag, isUserInitiated)
        }
    }
}

struct SAGitHubReleaseCheckTracker {
    private var currentID: UUID?
    private var currentIsUserInitiated = false

    mutating func begin(isUserInitiated: Bool) -> UUID? {
        if currentIsUserInitiated && !isUserInitiated {
            return nil
        }

        let id = UUID()
        currentID = id
        currentIsUserInitiated = isUserInitiated
        return id
    }

    func isCurrent(_ id: UUID) -> Bool {
        currentID == id
    }

    mutating func finish(_ id: UUID) {
        guard currentID == id else {
            return
        }

        currentID = nil
        currentIsUserInitiated = false
    }
}

enum SAGitHubReleasePagination {
    static let pageSize = 100
    static let maximumPageCount = 10

    static func nextPageURL(
        from linkHeader: String?,
        pagesFetched: Int,
        visitedPageURLs: Set<URL>,
        releases: [SAGitHubRelease],
        installedBuildName: String,
        installedReleaseTag: String?
    ) -> URL? {
        guard
            pagesFetched < maximumPageCount,
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
                url.host == "api.github.com",
                visitedPageURLs.contains(url) == false
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
