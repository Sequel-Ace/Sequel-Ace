//
//  GitHub.swift
//  Sequel Ace
//
//  Created by James on 13/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let gitHub = try GitHub(json)

import Foundation

// MARK: - GitHubElement
final class GitHubElement: Codable, Comparable {
    static func < (lhs: GitHubElement, rhs: GitHubElement) -> Bool {
        return lhs.publishedAt < rhs.publishedAt
    }

    static func > (lhs: GitHubElement, rhs: GitHubElement) -> Bool {
        return lhs.publishedAt > rhs.publishedAt
    }

    static func == (lhs: GitHubElement, rhs: GitHubElement) -> Bool {
        return lhs.publishedAt == rhs.publishedAt
    }

    let url, assetsURL: String
    let uploadURL: String
    let htmlURL: String
    let id: Int
    let author: Author
    let nodeID, tagName: String
    let targetCommitish: String
    let name: String
    let draft, prerelease: Bool
    let createdAt, publishedAt: Date
    let assets: [Asset]
    let tarballURL, zipballURL: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case url
        case assetsURL = "assets_url"
        case uploadURL = "upload_url"
        case htmlURL = "html_url"
        case id, author
        case nodeID = "node_id"
        case tagName = "tag_name"
        case targetCommitish = "target_commitish"
        case name, draft, prerelease
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case assets
        case tarballURL = "tarball_url"
        case zipballURL = "zipball_url"
        case body
    }

    init(url: String, assetsURL: String, uploadURL: String, htmlURL: String, id: Int, author: Author, nodeID: String, tagName: String, targetCommitish: String, name: String, draft: Bool, prerelease: Bool, createdAt: Date, publishedAt: Date, assets: [Asset], tarballURL: String, zipballURL: String, body: String) {
        self.url = url
        self.assetsURL = assetsURL
        self.uploadURL = uploadURL
        self.htmlURL = htmlURL
        self.id = id
        self.author = author
        self.nodeID = nodeID
        self.tagName = tagName
        self.targetCommitish = targetCommitish
        self.name = name
        self.draft = draft
        self.prerelease = prerelease
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.assets = assets
        self.tarballURL = tarballURL
        self.zipballURL = zipballURL
        self.body = body
    }
}

// MARK: GitHubElement convenience initializers and mutators

extension GitHubElement {
    convenience init(data: Data) throws {
        let me = try newJSONDecoder().decode(GitHubElement.self, from: data)
        self.init(url: me.url, assetsURL: me.assetsURL, uploadURL: me.uploadURL, htmlURL: me.htmlURL, id: me.id, author: me.author, nodeID: me.nodeID, tagName: me.tagName, targetCommitish: me.targetCommitish, name: me.name, draft: me.draft, prerelease: me.prerelease, createdAt: me.createdAt, publishedAt: me.publishedAt, assets: me.assets, tarballURL: me.tarballURL, zipballURL: me.zipballURL, body: me.body)
    }

    convenience init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    convenience init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        url: String? = nil,
        assetsURL: String? = nil,
        uploadURL: String? = nil,
        htmlURL: String? = nil,
        id: Int? = nil,
        author: Author? = nil,
        nodeID: String? = nil,
        tagName: String? = nil,
        targetCommitish: String? = nil,
        name: String? = nil,
        draft: Bool? = nil,
        prerelease: Bool? = nil,
        createdAt: Date? = nil,
        publishedAt: Date? = nil,
        assets: [Asset]? = nil,
        tarballURL: String? = nil,
        zipballURL: String? = nil,
        body: String? = nil
    ) -> GitHubElement {
        return GitHubElement(
            url: url ?? self.url,
            assetsURL: assetsURL ?? self.assetsURL,
            uploadURL: uploadURL ?? self.uploadURL,
            htmlURL: htmlURL ?? self.htmlURL,
            id: id ?? self.id,
            author: author ?? self.author,
            nodeID: nodeID ?? self.nodeID,
            tagName: tagName ?? self.tagName,
            targetCommitish: targetCommitish ?? self.targetCommitish,
            name: name ?? self.name,
            draft: draft ?? self.draft,
            prerelease: prerelease ?? self.prerelease,
            createdAt: createdAt ?? self.createdAt,
            publishedAt: publishedAt ?? self.publishedAt,
            assets: assets ?? self.assets,
            tarballURL: tarballURL ?? self.tarballURL,
            zipballURL: zipballURL ?? self.zipballURL,
            body: body ?? self.body
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Asset
final class Asset: Codable {
    let url: String
    let id: Int
    let nodeID, name: String
    let label: JSONNull?
    let uploader: Author
    let contentType: ContentType
    let state: State
    let size, downloadCount: Int
    let createdAt, updatedAt: Date
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case url, id
        case nodeID = "node_id"
        case name, label, uploader
        case contentType = "content_type"
        case state, size
        case downloadCount = "download_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case browserDownloadURL = "browser_download_url"
    }

    init(url: String, id: Int, nodeID: String, name: String, label: JSONNull?, uploader: Author, contentType: ContentType, state: State, size: Int, downloadCount: Int, createdAt: Date, updatedAt: Date, browserDownloadURL: String) {
        self.url = url
        self.id = id
        self.nodeID = nodeID
        self.name = name
        self.label = label
        self.uploader = uploader
        self.contentType = contentType
        self.state = state
        self.size = size
        self.downloadCount = downloadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.browserDownloadURL = browserDownloadURL
    }
}

// MARK: Asset convenience initializers and mutators

extension Asset {
    convenience init(data: Data) throws {
        let me = try newJSONDecoder().decode(Asset.self, from: data)
        self.init(url: me.url, id: me.id, nodeID: me.nodeID, name: me.name, label: me.label, uploader: me.uploader, contentType: me.contentType, state: me.state, size: me.size, downloadCount: me.downloadCount, createdAt: me.createdAt, updatedAt: me.updatedAt, browserDownloadURL: me.browserDownloadURL)
    }

    convenience init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    convenience init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        url: String? = nil,
        id: Int? = nil,
        nodeID: String? = nil,
        name: String? = nil,
        label: JSONNull?? = nil,
        uploader: Author? = nil,
        contentType: ContentType? = nil,
        state: State? = nil,
        size: Int? = nil,
        downloadCount: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        browserDownloadURL: String? = nil
    ) -> Asset {
        return Asset(
            url: url ?? self.url,
            id: id ?? self.id,
            nodeID: nodeID ?? self.nodeID,
            name: name ?? self.name,
            label: label ?? self.label,
            uploader: uploader ?? self.uploader,
            contentType: contentType ?? self.contentType,
            state: state ?? self.state,
            size: size ?? self.size,
            downloadCount: downloadCount ?? self.downloadCount,
            createdAt: createdAt ?? self.createdAt,
            updatedAt: updatedAt ?? self.updatedAt,
            browserDownloadURL: browserDownloadURL ?? self.browserDownloadURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

enum ContentType: String, Codable {
    case applicationZip = "application/zip"
}

enum State: String, Codable {
    case uploaded = "uploaded"
}

// MARK: - Author
final class Author: Codable {
    let login: Login
    let id: Int
    let nodeID: NodeID
    let avatarURL: String
    let gravatarID: String
    let url, htmlURL, followersURL: String
    let followingURL: FollowingURL
    let gistsURL: GistsURL
    let starredURL: StarredURL
    let subscriptionsURL, organizationsURL, reposURL: String
    let eventsURL: EventsURL
    let receivedEventsURL: String
    let type: TypeEnum
    let siteAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case login, id
        case nodeID = "node_id"
        case avatarURL = "avatar_url"
        case gravatarID = "gravatar_id"
        case url
        case htmlURL = "html_url"
        case followersURL = "followers_url"
        case followingURL = "following_url"
        case gistsURL = "gists_url"
        case starredURL = "starred_url"
        case subscriptionsURL = "subscriptions_url"
        case organizationsURL = "organizations_url"
        case reposURL = "repos_url"
        case eventsURL = "events_url"
        case receivedEventsURL = "received_events_url"
        case type
        case siteAdmin = "site_admin"
    }

    init(login: Login, id: Int, nodeID: NodeID, avatarURL: String, gravatarID: String, url: String, htmlURL: String, followersURL: String, followingURL: FollowingURL, gistsURL: GistsURL, starredURL: StarredURL, subscriptionsURL: String, organizationsURL: String, reposURL: String, eventsURL: EventsURL, receivedEventsURL: String, type: TypeEnum, siteAdmin: Bool) {
        self.login = login
        self.id = id
        self.nodeID = nodeID
        self.avatarURL = avatarURL
        self.gravatarID = gravatarID
        self.url = url
        self.htmlURL = htmlURL
        self.followersURL = followersURL
        self.followingURL = followingURL
        self.gistsURL = gistsURL
        self.starredURL = starredURL
        self.subscriptionsURL = subscriptionsURL
        self.organizationsURL = organizationsURL
        self.reposURL = reposURL
        self.eventsURL = eventsURL
        self.receivedEventsURL = receivedEventsURL
        self.type = type
        self.siteAdmin = siteAdmin
    }
}

// MARK: Author convenience initializers and mutators

extension Author {
    convenience init(data: Data) throws {
        let me = try newJSONDecoder().decode(Author.self, from: data)
        self.init(login: me.login, id: me.id, nodeID: me.nodeID, avatarURL: me.avatarURL, gravatarID: me.gravatarID, url: me.url, htmlURL: me.htmlURL, followersURL: me.followersURL, followingURL: me.followingURL, gistsURL: me.gistsURL, starredURL: me.starredURL, subscriptionsURL: me.subscriptionsURL, organizationsURL: me.organizationsURL, reposURL: me.reposURL, eventsURL: me.eventsURL, receivedEventsURL: me.receivedEventsURL, type: me.type, siteAdmin: me.siteAdmin)
    }

    convenience init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    convenience init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        login: Login? = nil,
        id: Int? = nil,
        nodeID: NodeID? = nil,
        avatarURL: String? = nil,
        gravatarID: String? = nil,
        url: String? = nil,
        htmlURL: String? = nil,
        followersURL: String? = nil,
        followingURL: FollowingURL? = nil,
        gistsURL: GistsURL? = nil,
        starredURL: StarredURL? = nil,
        subscriptionsURL: String? = nil,
        organizationsURL: String? = nil,
        reposURL: String? = nil,
        eventsURL: EventsURL? = nil,
        receivedEventsURL: String? = nil,
        type: TypeEnum? = nil,
        siteAdmin: Bool? = nil
    ) -> Author {
        return Author(
            login: login ?? self.login,
            id: id ?? self.id,
            nodeID: nodeID ?? self.nodeID,
            avatarURL: avatarURL ?? self.avatarURL,
            gravatarID: gravatarID ?? self.gravatarID,
            url: url ?? self.url,
            htmlURL: htmlURL ?? self.htmlURL,
            followersURL: followersURL ?? self.followersURL,
            followingURL: followingURL ?? self.followingURL,
            gistsURL: gistsURL ?? self.gistsURL,
            starredURL: starredURL ?? self.starredURL,
            subscriptionsURL: subscriptionsURL ?? self.subscriptionsURL,
            organizationsURL: organizationsURL ?? self.organizationsURL,
            reposURL: reposURL ?? self.reposURL,
            eventsURL: eventsURL ?? self.eventsURL,
            receivedEventsURL: receivedEventsURL ?? self.receivedEventsURL,
            type: type ?? self.type,
            siteAdmin: siteAdmin ?? self.siteAdmin
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

enum EventsURL: String, Codable {
    case httpsAPIGithubCOMUsersJasonMorcosEventsPrivacy = "https://api.github.com/users/Jason-Morcos/events{/privacy}"
    case httpsAPIGithubCOMUsersKaspikEventsPrivacy = "https://api.github.com/users/Kaspik/events{/privacy}"
}

enum FollowingURL: String, Codable {
    case httpsAPIGithubCOMUsersJasonMorcosFollowingOtherUser = "https://api.github.com/users/Jason-Morcos/following{/other_user}"
    case httpsAPIGithubCOMUsersKaspikFollowingOtherUser = "https://api.github.com/users/Kaspik/following{/other_user}"
}

enum GistsURL: String, Codable {
    case httpsAPIGithubCOMUsersJasonMorcosGistsGistID = "https://api.github.com/users/Jason-Morcos/gists{/gist_id}"
    case httpsAPIGithubCOMUsersKaspikGistsGistID = "https://api.github.com/users/Kaspik/gists{/gist_id}"
}

enum Login: String, Codable {
    case jasonMorcos = "Jason-Morcos"
    case kaspik = "Kaspik"
}

enum NodeID: String, Codable {
    case mdq6VXNlcjEwNzEwMzY3 = "MDQ6VXNlcjEwNzEwMzY3"
    case mdq6VXNlcjcyMDQxNjg = "MDQ6VXNlcjcyMDQxNjg="
}

enum StarredURL: String, Codable {
    case httpsAPIGithubCOMUsersJasonMorcosStarredOwnerRepo = "https://api.github.com/users/Jason-Morcos/starred{/owner}{/repo}"
    case httpsAPIGithubCOMUsersKaspikStarredOwnerRepo = "https://api.github.com/users/Kaspik/starred{/owner}{/repo}"
}

enum TypeEnum: String, Codable {
    case user = "User"
}

typealias GitHub = [GitHubElement]

extension Array where Element == GitHub.Element {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(GitHub.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Helper functions for creating encoders and decoders

func newJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

func newJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

// MARK: - Encode/decode helpers

final class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        return true
    }

    public var hashValue: Int {
        return 0
    }

    public func hash(into hasher: inout Hasher) {
        // No-op
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
