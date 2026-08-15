# frozen_string_literal: true

module SequelAceRelease
  class LegacyReleasePayload
    # Sequel Ace 5.3.1 and earlier generated enums from this exact subset of
    # GitHub's user object. A different value makes the entire releases page
    # undecodable before those clients can filter drafts or prereleases.
    JASON_IDENTITY = {
      "id" => ReleasePublisher::USER_ID,
      "node_id" => "MDQ6VXNlcjEwNzEwMzY3",
      "type" => "User",
      "following_url" => "https://api.github.com/users/Jason-Morcos/following{/other_user}",
      "gists_url" => "https://api.github.com/users/Jason-Morcos/gists{/gist_id}",
      "starred_url" => "https://api.github.com/users/Jason-Morcos/starred{/owner}{/repo}",
      "events_url" => "https://api.github.com/users/Jason-Morcos/events{/privacy}"
    }.freeze
    EXPECTED_ASSET_FIELDS = {
      "content_type" => "application/zip",
      "state" => "uploaded"
    }.freeze

    def self.required?(release)
      ReleasePublisher.legacy_client_compatibility_required?(
        tag: release.fetch("tag_name"),
        created_at: release.fetch("created_at")
      )
    rescue KeyError
      raise ValidationError, "GitHub release has malformed legacy compatibility provenance"
    end

    def initialize(release:, expected_digests:)
      @release = release
      @expected_digests = expected_digests
    end

    def validate
      validate_expected_digests!
      legacy_required = self.class.required?(@release)
      validate_jason!(@release["author"], "release author") if legacy_required

      assets = Array(@release["assets"])
      unless assets.all? { |asset| asset.is_a?(Hash) && asset["name"].is_a?(String) && !asset["name"].empty? }
        raise IntegrityError, "GitHub release asset metadata is malformed"
      end
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
        name = asset.fetch("name")
        validate_asset!(asset, name: name, legacy_required: legacy_required)
      rescue KeyError
        raise IntegrityError, "GitHub release asset metadata is malformed"
      end

      missing = @expected_digests.keys - actual_names
      {
        "ready" => missing.empty?,
        "mode" => legacy_required ? "manual_web_upload" : "api_upload",
        "legacy_compatibility_required" => legacy_required,
        "missing_assets" => missing.sort,
        "verified_assets" => (actual_names & @expected_digests.keys).sort
      }
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

    def validate_asset!(asset, name:, legacy_required:)
      expected_digest = @expected_digests.fetch(name).downcase
      actual_digest = asset["digest"].to_s.delete_prefix("sha256:").downcase
      unless actual_digest == expected_digest
        raise IntegrityError, "GitHub asset checksum mismatch for #{name}"
      end
      EXPECTED_ASSET_FIELDS.each do |field, expected|
        unless asset[field] == expected
          raise IntegrityError, "GitHub asset #{name} has incompatible #{field.tr('_', ' ')}"
        end
      end
      return unless legacy_required

      unless asset.key?("label") && asset["label"].nil?
        raise IntegrityError, "GitHub asset #{name} must encode label as JSON null for legacy clients"
      end
      validate_jason!(asset["uploader"], "asset uploader for #{name}")
    end

    def validate_jason!(author, label)
      unless author.is_a?(Hash)
        raise IntegrityError, "GitHub #{label} metadata is malformed"
      end
      unless author["login"] == ReleasePublisher::USER_LOGIN
        raise IntegrityError, "GitHub #{label} is incompatible with legacy Sequel Ace clients"
      end
      mismatched = JASON_IDENTITY.any? { |field, value| author[field] != value }
      if mismatched
        raise IntegrityError, "GitHub #{label} identity is incompatible with legacy Sequel Ace clients"
      end
    end
  end
end
