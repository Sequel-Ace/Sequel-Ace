# frozen_string_literal: true

module SequelAceRelease
  class PublishHandoff
    RELEASE_PATHS = (Config::PROJECT_FILES.keys + Config::PLIST_FILES + ["CHANGELOG.md"]).freeze
    STRICT_RELEASE_PATHS = (Config::PLIST_FILES + ["CHANGELOG.md"]).freeze
    ELIGIBLE_STATES = {
      "production" => %w[cloud_running artifacts_verified archived],
      "beta" => %w[cloud_running artifacts_verified]
    }.freeze

    def initialize(github:)
      @github = github
    end

    def self.validate_release_source!(github:, target_sha:, canonical_build:)
      validation = github.validate_release_target!(
        target_sha: target_sha,
        protected_paths: STRICT_RELEASE_PATHS
      )
      [target_sha, validation.fetch("current_main_sha")].uniq.each do |ref|
        contents = Config::PROJECT_FILES.keys.to_h do |path|
          [path, github.file_content(ref: ref, path: path)]
        end
        VersionFiles.validate_project_build_settings!(
          contents_by_path: contents,
          expected_build: canonical_build
        )
      end

      validation.merge("semantically_validated_project_paths" => Config::PROJECT_FILES.keys)
    end

    def validate(manifest:, tag:, app_store_notes:)
      # Release notes are maintainer-owned editorial content and intentionally
      # remain mutable throughout publication. The notes file is retained as a
      # compatibility input for callers and as the independently approved App
      # Store metadata; GitHub body edits neither rewrite nor invalidate it.
      data = manifest.to_h
      raise ValidationError, "archive tag does not match the candidate" unless data.fetch("tag") == tag

      naming = ReleaseNaming.new(
        channel: data.fetch("channel"),
        version: data.fetch("target_version"),
        build: data.fetch("canonical_build"),
        iteration: data.fetch("iteration")
      )
      unless data.fetch("tag") == naming.tag && data.fetch("title") == naming.title &&
             data.fetch("artifact_names") == naming.public_artifacts
        raise ValidationError, "archive release identity is not canonical"
      end

      release_commit = data.fetch("release_commit_sha")
      raise ValidationError, "release tag moved" unless @github.ref_sha("tags/#{tag}") == release_commit

      self.class.validate_release_source!(
        github: @github,
        target_sha: release_commit,
        canonical_build: data.fetch("canonical_build")
      )

      release = @github.release_by_tag(tag)
      raise ValidationError, "release tag identity changed" unless release["tag_name"] == tag
      raise ValidationError, "release must not be a draft" unless release["draft"] == false
      raise ValidationError, "release must remain a prerelease" unless release["prerelease"] == true
      raise ValidationError, "release title changed" unless release["name"] == data.fetch("title")
      ReleasePublisher.validate!(
        tag: tag,
        login: release.dig("author", "login"),
        id: release.dig("author", "id")
      )
      release_id = release["id"]
      unless release_id.is_a?(Integer) && release_id.positive?
        raise ValidationError, "release ID is malformed"
      end

      expected_assets = data.fetch("artifact_names")
      assets = release["assets"]
      valid_assets = assets.is_a?(Array) && assets.all? do |asset|
        asset.is_a?(Hash) && asset["name"].is_a?(String) && !asset["name"].empty?
      end
      unless valid_assets
        raise IntegrityError, "release asset metadata is malformed"
      end
      actual_assets = assets.map { |asset| asset["name"] }
      unexpected_assets = actual_assets - expected_assets
      unless unexpected_assets.empty?
        raise IntegrityError, "release has unexpected artifacts: #{unexpected_assets.join(', ')}"
      end

      state = data.fetch("state")
      if %w[archived submitted finalizing live].include?(state)
        missing_assets = expected_assets - actual_assets
        unless missing_assets.empty?
          raise IntegrityError, "archived release is missing artifacts: #{missing_assets.join(', ')}"
        end
        expected_digests = verify_asset_digests!(
          manifest: data,
          assets: assets,
          expected_names: expected_assets
        )
        GitHubReleasePayload.new(release: release, expected_digests: expected_digests).validate
      end

      alpha_recovery = validate_alpha_recovery!(data)
      eligible = ELIGIBLE_STATES.fetch(data.fetch("channel")).include?(state)

      {
        "eligible" => eligible,
        "state" => state,
        "channel" => data.fetch("channel"),
        "version" => data.fetch("target_version"),
        "build" => data.fetch("canonical_build"),
        "iteration" => data.fetch("iteration"),
        "tag" => tag,
        "title" => data.fetch("title"),
        "github_release_id" => release_id,
        "release_commit_sha" => release_commit,
        "artifact_names" => expected_assets,
        "cloud_build_ids" => data.fetch("cloud_build_ids"),
        "alpha_recovery" => alpha_recovery,
        "release_notes_mutable" => true
      }
    end

    private

    def validate_alpha_recovery!(manifest)
      return false unless manifest.key?("alpha_retry")
      raise ValidationError, "Alpha recovery is beta-only" unless manifest.fetch("channel") == "beta"

      retry_data = manifest.fetch("alpha_retry")
      raise ValidationError, "Alpha recovery evidence is malformed" unless retry_data.is_a?(Hash)

      predecessor = manifest.fetch("alpha_retry_predecessor", nil)
      unless predecessor.is_a?(Hash)
        raise ValidationError, "Alpha recovery evidence has malformed predecessor data"
      end
      durable_failed_id = predecessor["durable_failed_run_id"].to_s
      authorized_failed_id = predecessor["authorized_failed_run_id"].to_s
      unless [durable_failed_id, authorized_failed_id].all? { |value| value.match?(/\A[A-Za-z0-9-]+\z/) }
        raise ValidationError, "Alpha recovery evidence has malformed predecessor run identity"
      end
      unless durable_failed_id == manifest.dig("failure", "cloud_run_id").to_s
        raise ValidationError, "Alpha recovery evidence predecessor does not match the durable failed run"
      end

      required = %w[id workflow_id git_reference retried_failed_run_id reused_existing_retry]
      missing = required.select { |key| !retry_data.key?(key) }
      unless missing.empty?
        raise ValidationError, "Alpha recovery evidence is missing: #{missing.join(', ')}"
      end
      unless retry_data.fetch("id").to_s.match?(/\A[A-Za-z0-9-]+\z/) &&
             retry_data.fetch("workflow_id").to_s.match?(/\A[A-Za-z0-9-]+\z/)
        raise ValidationError, "Alpha recovery run identity is malformed"
      end
      unless retry_data.fetch("retried_failed_run_id") == authorized_failed_id
        raise ValidationError, "Alpha recovery evidence does not match the authorized failed run"
      end
      unless retry_data.fetch("reused_existing_retry") == true || retry_data.fetch("reused_existing_retry") == false
        raise ValidationError, "Alpha recovery reuse evidence is malformed"
      end
      unless retry_data.fetch("id") == manifest.fetch("cloud_build_ids").fetch("alpha", nil) &&
             retry_data.fetch("git_reference") == manifest.fetch("tag")
        raise ValidationError, "Alpha recovery evidence does not match the archived release"
      end
      commits = [retry_data["source_commit"], retry_data["destination_commit"]].compact
      unless commits.include?(manifest.fetch("release_commit_sha"))
        raise ValidationError, "Alpha recovery evidence does not match the release commit"
      end

      true
    end

    def verify_asset_digests!(manifest:, assets:, expected_names:)
      verification = manifest.fetch("verification", {})
      expected_digests = verification.each_with_object({}) do |(_channel, value), result|
        next unless value.is_a?(Hash) && value["zip_path"] && value["zip_sha256"]

        name = File.basename(value["zip_path"])
        raise IntegrityError, "private manifest has duplicate artifact checksums for #{name}" if result.key?(name)

        result[name] = value["zip_sha256"].to_s.downcase
      end
      missing = expected_names - expected_digests.keys
      unless missing.empty?
        raise IntegrityError, "private manifest is missing artifact checksums: #{missing.join(', ')}"
      end

      expected_names.each do |name|
        expected = expected_digests.fetch(name)
        unless expected.match?(/\A[0-9a-f]{64}\z/)
          raise IntegrityError, "private manifest has a malformed checksum for #{name}"
        end
        asset = assets.find { |candidate| candidate["name"] == name }
        actual = asset&.fetch("digest", "").to_s.delete_prefix("sha256:").downcase
        raise IntegrityError, "GitHub asset checksum mismatch for #{name}" unless actual == expected
      end
      expected_digests
    end
  end
end
