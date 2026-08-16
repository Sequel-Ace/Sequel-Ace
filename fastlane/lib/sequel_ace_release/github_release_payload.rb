# frozen_string_literal: true

require "time"

module SequelAceRelease
  class GitHubReleasePayload
    LEGACY_UPDATER_PROFILE = "legacy_updater_v1".freeze
    GITHUB_API_PROFILE = "github_api_v1".freeze
    PROFILE_MODES = {
      LEGACY_UPDATER_PROFILE => "manual_web_upload",
      GITHUB_API_PROFILE => "api_upload"
    }.freeze

    # Sequel Ace 5.3.1 and earlier generated enums from a GitHub response that
    # contained these two users. The remaining author fields were ordinary
    # Codable primitives, so validate their types without pinning values that
    # GitHub may legitimately change.
    LEGACY_USER_ENUMS = {
      "Jason-Morcos" => {
        "node_id" => "MDQ6VXNlcjEwNzEwMzY3",
        "following_url" => "https://api.github.com/users/Jason-Morcos/following{/other_user}",
        "gists_url" => "https://api.github.com/users/Jason-Morcos/gists{/gist_id}",
        "starred_url" => "https://api.github.com/users/Jason-Morcos/starred{/owner}{/repo}",
        "events_url" => "https://api.github.com/users/Jason-Morcos/events{/privacy}"
      }.freeze,
      "Kaspik" => {
        "node_id" => "MDQ6VXNlcjcyMDQxNjg=",
        "following_url" => "https://api.github.com/users/Kaspik/following{/other_user}",
        "gists_url" => "https://api.github.com/users/Kaspik/gists{/gist_id}",
        "starred_url" => "https://api.github.com/users/Kaspik/starred{/owner}{/repo}",
        "events_url" => "https://api.github.com/users/Kaspik/events{/privacy}"
      }.freeze
    }.freeze
    LEGACY_RELEASE_STRING_FIELDS = %w[
      url assets_url upload_url html_url node_id tag_name target_commitish name
      tarball_url zipball_url body
    ].freeze
    LEGACY_AUTHOR_STRING_FIELDS = %w[
      login node_id avatar_url gravatar_id url html_url followers_url
      following_url gists_url starred_url subscriptions_url organizations_url
      repos_url events_url received_events_url type
    ].freeze
    LEGACY_ASSET_STRING_FIELDS = %w[
      url node_id name content_type state browser_download_url
    ].freeze
    EXPECTED_ASSET_FIELDS = {
      "content_type" => "application/zip",
      "state" => "uploaded"
    }.freeze
    TARGET_FEED_RELEASE_FIELDS = %w[name html_url draft prerelease published_at].freeze
    TARGET_FEED_AUTHOR_FIELDS = %w[id login type].freeze
    TARGET_FEED_ASSET_FIELDS = %w[id size browser_download_url].freeze
    ZONED_TIMESTAMP_PATTERN = /(?:Z|[+-]\d{2}:\d{2})\z/.freeze

    def self.profile_for(release)
      unless release.is_a?(Hash) && release["author"].is_a?(Hash) &&
             release.dig("author", "login").is_a?(String) && !release.dig("author", "login").empty?
        raise IntegrityError, "GitHub release author metadata is malformed"
      end

      return LEGACY_UPDATER_PROFILE if LEGACY_USER_ENUMS.key?(release.dig("author", "login"))

      GITHUB_API_PROFILE
    end

    def initialize(release:, expected_digests:)
      @release = release
      @expected_digests = expected_digests
    end

    def validate
      validate_expected_digests!
      profile = self.class.profile_for(@release)
      validate_release_envelope!
      validate_legacy_release! if profile == LEGACY_UPDATER_PROFILE

      assets = @release.fetch("assets")
      actual_names = assets.map { |asset| asset["name"] }
      duplicates = actual_names.tally.select { |_name, count| count > 1 }.keys
      unless duplicates.empty?
        raise IntegrityError, "GitHub release has duplicate artifacts: #{duplicates.sort.join(', ')}"
      end
      unexpected = actual_names - @expected_digests.keys
      unless unexpected.empty?
        raise IntegrityError, "GitHub release has unexpected artifacts: #{unexpected.sort.join(', ')}"
      end

      assets.each do |asset|
        validate_asset!(asset, profile: profile)
      end

      missing = @expected_digests.keys - actual_names
      {
        "ready" => missing.empty?,
        "mode" => PROFILE_MODES.fetch(profile),
        "compatibility_profile" => profile,
        "compatible_uploaders" => profile == LEGACY_UPDATER_PROFILE ? LEGACY_USER_ENUMS.keys.sort : [],
        "missing_assets" => missing.sort,
        "verified_assets" => (actual_names & @expected_digests.keys).sort
      }
    rescue KeyError
      raise IntegrityError, "GitHub release asset metadata is malformed"
    end

    def validate_public_feed!(releases)
      unless releases.is_a?(Array) && !releases.empty?
        raise IntegrityError, "GitHub release feed metadata is malformed"
      end

      if self.class.profile_for(@release) == LEGACY_UPDATER_PROFILE
        releases.each_with_index do |release, index|
          validate_legacy_release!(release)
          release.fetch("assets").each { |asset| validate_legacy_asset_shape!(asset) }
        rescue IntegrityError, KeyError => error
          raise IntegrityError,
                "GitHub release feed entry #{index + 1} is not legacy-decodable: #{error.message}"
        end
      end
      target_matches = releases.select do |release|
        release.is_a?(Hash) && release["id"] == @release["id"] && release["tag_name"] == @release["tag_name"]
      end
      if target_matches.empty?
        raise IntegrityError, "exact GitHub release is absent from the public release feed"
      end
      unless target_matches.one?
        raise IntegrityError, "exact GitHub release appears more than once in the public release feed"
      end

      target_status = self.class.new(
        release: target_matches.first,
        expected_digests: @expected_digests
      ).validate
      unless target_status.fetch("ready")
        raise IntegrityError,
              "exact GitHub release is missing artifacts from the public release feed: " \
              "#{target_status.fetch('missing_assets').join(', ')}"
      end
      validate_target_feed_match!(target_matches.first)

      releases.length
    end

    private

    def validate_expected_digests!
      unless @expected_digests.is_a?(Hash) && !@expected_digests.empty?
        raise IntegrityError, "private manifest has no release artifact checksums"
      end
      @expected_digests.each do |name, digest|
        unless name.is_a?(String) && !name.empty? && File.basename(name) == name &&
               digest.to_s.match?(/\A[0-9a-f]{64}\z/i)
          raise IntegrityError, "private manifest has malformed release artifact checksums"
        end
      end
    end

    def validate_release_envelope!
      unless @release.is_a?(Hash) && positive_integer?(@release["id"]) &&
             @release["tag_name"].is_a?(String) && !@release["tag_name"].empty? &&
             @release["assets"].is_a?(Array) && @release["assets"].all? { |asset| valid_asset_envelope?(asset) }
        raise IntegrityError, "GitHub release asset metadata is malformed"
      end
    end

    def valid_asset_envelope?(asset)
      asset.is_a?(Hash) && asset["name"].is_a?(String) && !asset["name"].empty?
    end

    def validate_legacy_release!(release = @release)
      unless release.is_a?(Hash) && release["assets"].is_a?(Array)
        raise IntegrityError, "GitHub release metadata is malformed"
      end
      validate_string_fields!(release, LEGACY_RELEASE_STRING_FIELDS, "release")
      validate_integer_field!(release, "id", "release", positive: true)
      validate_boolean_field!(release, "draft", "release")
      validate_boolean_field!(release, "prerelease", "release")
      validate_timestamp_field!(release, "created_at", "release")
      validate_timestamp_field!(release, "published_at", "release")
      validate_legacy_user!(release["author"], "release author")
    end

    def validate_asset!(asset, profile:)
      name = asset.fetch("name")
      expected_digest = @expected_digests.fetch(name).downcase
      actual_digest = asset["digest"].to_s.delete_prefix("sha256:").downcase
      unless actual_digest == expected_digest
        raise IntegrityError, "GitHub asset checksum mismatch for #{name}"
      end
      validate_asset_state!(asset, name)
      return unless profile == LEGACY_UPDATER_PROFILE

      validate_legacy_asset_shape!(asset)
    end

    def validate_legacy_asset_shape!(asset)
      unless asset.is_a?(Hash)
        raise IntegrityError, "GitHub release asset metadata is malformed"
      end
      name = asset["name"].to_s
      validate_string_fields!(asset, LEGACY_ASSET_STRING_FIELDS, "asset #{name}")
      validate_integer_field!(asset, "id", "asset #{name}", positive: true)
      validate_integer_field!(asset, "size", "asset #{name}", positive: true)
      validate_integer_field!(asset, "download_count", "asset #{name}", positive: false)
      validate_timestamp_field!(asset, "created_at", "asset #{name}")
      validate_timestamp_field!(asset, "updated_at", "asset #{name}")
      unless asset.key?("label") && asset["label"].nil?
        raise IntegrityError, "GitHub asset #{name} must encode label as JSON null for legacy clients"
      end
      validate_asset_state!(asset, name)
      validate_legacy_user!(asset["uploader"], "asset uploader for #{name}")
    end

    def validate_asset_state!(asset, name)
      EXPECTED_ASSET_FIELDS.each do |field, expected|
        unless asset[field] == expected
          raise IntegrityError, "GitHub asset #{name} has incompatible #{field.tr('_', ' ')}"
        end
      end
    end

    def validate_target_feed_match!(target)
      TARGET_FEED_RELEASE_FIELDS.each do |field|
        next if target[field] == @release[field]

        raise IntegrityError,
              "exact GitHub release field #{field.tr('_', ' ')} differs between authenticated and anonymous responses"
      end
      TARGET_FEED_AUTHOR_FIELDS.each do |field|
        next if target.dig("author", field) == @release.dig("author", field)

        raise IntegrityError,
              "exact GitHub release author field #{field.tr('_', ' ')} differs between authenticated and " \
              "anonymous responses"
      end

      expected_assets = @release.fetch("assets").to_h { |asset| [asset.fetch("name"), asset] }
      target.fetch("assets").each do |asset|
        expected = expected_assets.fetch(asset.fetch("name"))
        TARGET_FEED_ASSET_FIELDS.each do |field|
          next if asset[field] == expected[field]

          raise IntegrityError,
                "exact GitHub asset #{asset.fetch('name')} field #{field.tr('_', ' ')} differs between " \
                "authenticated and anonymous responses"
        end
      end
    rescue KeyError, TypeError
      raise IntegrityError, "exact GitHub release differs between authenticated and anonymous responses"
    end

    def validate_legacy_user!(user, label)
      unless user.is_a?(Hash)
        raise IntegrityError, "GitHub #{label} metadata is malformed"
      end
      validate_string_fields!(user, LEGACY_AUTHOR_STRING_FIELDS, label, allow_empty: ["gravatar_id"])
      validate_integer_field!(user, "id", label, positive: true)
      validate_boolean_field!(user, "site_admin", label)

      enums = LEGACY_USER_ENUMS[user["login"]]
      unless enums && user["type"] == "User" && enums.all? { |field, value| user[field] == value }
        raise IntegrityError, "GitHub #{label} identity is incompatible with legacy Sequel Ace clients"
      end
    end

    def validate_string_fields!(value, fields, label, allow_empty: ["body"])
      invalid = fields.find do |field|
        !value[field].is_a?(String) || (value[field].empty? && !allow_empty.include?(field))
      end
      return unless invalid

      raise IntegrityError, "GitHub #{label} field #{invalid.tr('_', ' ')} is incompatible with legacy clients"
    end

    def validate_integer_field!(value, field, label, positive:)
      integer = value[field]
      valid = integer.is_a?(Integer) && (positive ? integer.positive? : !integer.negative?)
      return if valid

      raise IntegrityError, "GitHub #{label} field #{field.tr('_', ' ')} is incompatible with legacy clients"
    end

    def validate_boolean_field!(value, field, label)
      return if value[field] == true || value[field] == false

      raise IntegrityError, "GitHub #{label} field #{field.tr('_', ' ')} is incompatible with legacy clients"
    end

    def validate_timestamp_field!(value, field, label)
      timestamp = value[field]
      Time.iso8601(timestamp) if timestamp.is_a?(String)
      return if timestamp.is_a?(String) && timestamp.match?(ZONED_TIMESTAMP_PATTERN)

      raise ArgumentError
    rescue ArgumentError, TypeError
      raise IntegrityError, "GitHub #{label} field #{field.tr('_', ' ')} is incompatible with legacy clients"
    end

    def positive_integer?(value)
      value.is_a?(Integer) && value.positive?
    end
  end
end
