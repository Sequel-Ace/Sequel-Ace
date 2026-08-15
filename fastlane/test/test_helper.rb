# frozen_string_literal: true

require "minitest/autorun"
require "base64"
require "digest"
require "json"
require "tmpdir"
require "fileutils"
require "stringio"
require "sequel_ace_release"

module ReleaseTestHelpers
  class FakeTransport
    attr_reader :requests

    def initialize(responses)
      @responses = responses.dup
      @requests = []
    end

    def request(method, path, query: nil, body: nil, headers: {})
      @requests << { method: method, path: path, query: query, body: body, headers: headers }
      response = @responses.shift
      raise "no fake response left for #{method} #{path}" unless response

      response.respond_to?(:call) ? response.call(@requests.last) : response
    end
  end

  def http_response(status: 200, body: {}, headers: {})
    SequelAceRelease::HTTPTransport::Response.new(status: status, body: body, headers: headers)
  end

  def fixture_json(path)
    JSON.parse(File.read(File.join(__dir__, "fixtures", path)))
  end

  def approval(overrides = {})
    SequelAceRelease::Approval.new(**{
      channel: "production",
      target_version: "5.3.2",
      main_sha: "a" * 40,
      previous_tag: "production/5.3.1-20104",
      base_sha: "b" * 40,
      changelog_base_tag: "production/5.3.1-20104",
      changelog_base_sha: "b" * 40,
      app_store_notes: "A focused release note.",
      release_notes_sha256: "c" * 64
    }.merge(overrides))
  end

  def complete_screenshots(count = 10)
    Array.new(count) do |index|
      {
        "id" => "screenshot-#{index}",
        "attributes" => { "assetDeliveryState" => { "state" => "COMPLETE" } }
      }
    end
  end

  def production_build_evidence(target: 20_105)
    highest = target - 1
    {
      "policy" => SequelAceRelease::Approval::POLICY,
      "source_build" => highest,
      "highest_tag_build" => highest,
      "highest_asc_build" => highest,
      "highest_cloud_build" => highest,
      "highest_observed_build" => highest,
      "expected_next_build" => target
    }
  end

  def metadata_snapshot(build: 20_105, state: "PREPARE_FOR_SUBMISSION", phased_state: "INACTIVE")
    {
      "version" => {
        "id" => "version-id",
        "attributes" => {
          "appStoreState" => state,
          "releaseType" => "SCHEDULED",
          "earliestReleaseDate" => "2026-08-12T16:00:00Z"
        }
      },
      "localization" => {
        "id" => "localization-id",
        "attributes" => {
          "locale" => "en-US",
          "description" => "Description",
          "keywords" => "mysql,database",
          "whatsNew" => "A focused release note.",
          "promotionalText" => "A native database client.",
          "supportUrl" => "https://sequel-ace.com/support",
          "marketingUrl" => "https://sequel-ace.com"
        }
      },
      "screenshot_sets" => [{ "id" => "set-id", "screenshots" => complete_screenshots }],
      "review_detail" => {
        "id" => "review-id",
        "attributes" => {
          "contactFirstName" => "Release",
          "contactLastName" => "Manager",
          "contactEmail" => "release@example.invalid",
          "contactPhone" => "+10000000000",
          "demoAccountRequired" => false
        }
      },
      "phased_release" => {
        "id" => "phase-id",
        "attributes" => { "phasedReleaseState" => phased_state }
      },
      "selected_build" => {
        "id" => "build-id",
        "attributes" => { "version" => build.to_s }
      },
      "reset_ratings_request" => nil
    }
  end

  def legacy_github_user(login: "Jason-Morcos")
    identities = {
      "Jason-Morcos" => [10_710_367, "MDQ6VXNlcjEwNzEwMzY3"],
      "Kaspik" => [7_204_168, "MDQ6VXNlcjcyMDQxNjg="]
    }
    id, node_id = identities.fetch(login)
    {
      "login" => login,
      "id" => id,
      "node_id" => node_id,
      "avatar_url" => "https://avatars.githubusercontent.com/u/#{id}?v=4",
      "gravatar_id" => "",
      "url" => "https://api.github.com/users/#{login}",
      "html_url" => "https://github.com/#{login}",
      "followers_url" => "https://api.github.com/users/#{login}/followers",
      "following_url" => "https://api.github.com/users/#{login}/following{/other_user}",
      "gists_url" => "https://api.github.com/users/#{login}/gists{/gist_id}",
      "starred_url" => "https://api.github.com/users/#{login}/starred{/owner}{/repo}",
      "subscriptions_url" => "https://api.github.com/users/#{login}/subscriptions",
      "organizations_url" => "https://api.github.com/users/#{login}/orgs",
      "repos_url" => "https://api.github.com/users/#{login}/repos",
      "events_url" => "https://api.github.com/users/#{login}/events{/privacy}",
      "received_events_url" => "https://api.github.com/users/#{login}/received_events",
      "type" => "User",
      "site_admin" => false
    }
  end

  def github_release_payload(
    tag: "production/5.4.0-20109", title: "5.4.0 (20109)", body: "Release notes.",
    author: legacy_github_user, assets: [], id: 100, prerelease: true,
    created_at: "2026-08-13T00:00:00Z"
  )
    {
      "url" => "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases/#{id}",
      "assets_url" => "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases/#{id}/assets",
      "upload_url" => "https://uploads.github.com/repos/Sequel-Ace/Sequel-Ace/releases/#{id}/assets{?name,label}",
      "html_url" => "https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/#{tag}",
      "id" => id,
      "author" => author,
      "node_id" => "release-node-#{id}",
      "tag_name" => tag,
      "target_commitish" => "d" * 40,
      "name" => title,
      "draft" => false,
      "prerelease" => prerelease,
      "created_at" => created_at,
      "published_at" => created_at,
      "assets" => assets,
      "tarball_url" => "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/tarball/#{tag}",
      "zipball_url" => "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/zipball/#{tag}",
      "body" => body
    }
  end

  def github_release_asset(
    name:, digest:, uploader: legacy_github_user, label: nil, id: 200,
    created_at: "2026-08-13T00:05:00Z"
  )
    {
      "url" => "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases/assets/#{id}",
      "id" => id,
      "node_id" => "asset-node-#{id}",
      "name" => name,
      "label" => label,
      "uploader" => uploader,
      "content_type" => "application/zip",
      "state" => "uploaded",
      "size" => 42,
      "digest" => "sha256:#{digest}",
      "download_count" => 0,
      "created_at" => created_at,
      "updated_at" => created_at,
      "browser_download_url" => "https://github.com/Sequel-Ace/Sequel-Ace/releases/download/release/#{name}"
    }
  end
end

class Minitest::Test
  include ReleaseTestHelpers
end
