# frozen_string_literal: true

require "digest"

module SequelAceRelease
  class ForwardBuildRecovery
    MAX_AUTOMATIC_RECOVERIES = 3

    def initialize(github:)
      @github = github
    end

    def validate(
      manifest:, approval:, approval_sha:, release_body:, tag:, current_sha:,
      channel:, version:, previous_tag:
    )
      data = manifest.to_h
      approval.verify!(approval_sha)
      validate_identity!(
        data: data,
        approval: approval,
        release_body: release_body,
        tag: tag,
        current_sha: current_sha,
        channel: channel,
        version: version,
        previous_tag: previous_tag
      )

      failure = data["failure"]
      unless failure.is_a?(Hash) && failure["reason"] == "cloud_build_number_advanced"
        raise ValidationError, "forward recovery requires a durable Production Cloud number-advance failure"
      end
      expected = positive_integer(failure["expected_build"], "failed expected build")
      assigned = positive_integer(failure["assigned_build"], "Cloud-assigned build")
      recovery = positive_integer(failure["recovery_build"], "recovery build")
      unless expected == data.fetch("canonical_build") && assigned > expected && recovery == assigned + 1
        raise ValidationError, "forward recovery build evidence is inconsistent"
      end
      unless failure["cloud_run_id"].to_s.match?(/\A[A-Za-z0-9-]+\z/)
        raise ValidationError, "forward recovery is missing the exact mismatched Cloud run"
      end

      predecessor_count = begin
        Integer(data.dig("forward_build_recovery", "count") || 0)
      rescue ArgumentError, TypeError
        raise ValidationError, "forward recovery count must be an integer"
      end
      recovery_count = predecessor_count + 1
      if recovery_count > MAX_AUTOMATIC_RECOVERIES
        raise ValidationError,
              "automatic forward recovery limit (#{MAX_AUTOMATIC_RECOVERIES}) reached"
      end

      validate_github_release!(data, tag)
      {
        "predecessor_tag" => tag,
        "predecessor_manifest_schema" => data.fetch("schema_version"),
        "predecessor_release_commit_sha" => data.fetch("release_commit_sha"),
        "failed_expected_build" => expected,
        "cloud_assigned_build" => assigned,
        "expected_recovery_build" => recovery,
        "cloud_run_id" => failure.fetch("cloud_run_id"),
        "count" => recovery_count,
        "approval_sha256" => approval_sha
      }
    end

    private

    def validate_identity!(data:, approval:, release_body:, tag:, current_sha:, channel:, version:, previous_tag:)
      raise ValidationError, "forward recovery requires manifest schema 2" unless data["schema_version"] == Config::SCHEMA_VERSION
      raise ValidationError, "forward recovery requires a failed handoff" unless data["state"] == "failed"
      raise ValidationError, "recovery tag does not match the archived handoff" unless data["tag"] == tag
      raise ValidationError, "recovery channel does not match the archived handoff" unless data["channel"] == channel
      raise ValidationError, "recovery version does not match the archived handoff" unless data["target_version"] == version
      unless data["base_tag"] == previous_tag && approval.payload.fetch("previous_tag") == previous_tag
        raise ValidationError, "recovery comparison tag does not match the approved plan"
      end
      unless data["build_policy"] == Approval::POLICY && approval.payload.fetch("build_policy") == Approval::POLICY
        raise ValidationError, "recovery build policy is not forward-only"
      end
      unless approval.payload.fetch("channel") == channel && approval.payload.fetch("target_version") == version
        raise ValidationError, "recovery inputs do not match the immutable approval"
      end
      unless data["main_sha"] == approval.payload.fetch("main_sha")
        raise ValidationError, "recovery manifest does not match the frozen main SHA"
      end
      unless Config.valid_git_sha?(current_sha) && data["release_commit_sha"] == current_sha.downcase
        raise ValidationError, "automatic recovery requires main to remain at the failed release commit"
      end
      unless Digest::SHA256.hexdigest(release_body) == data["release_notes_sha256"] &&
             data["release_notes_sha256"] == approval.payload.fetch("release_notes_sha256")
        raise ValidationError, "recovery release body does not match the immutable approval"
      end
      approved_notes = Notes.app_store_notes_from_github_body(release_body)
      unless approved_notes == approval.payload.fetch("app_store_notes")
        raise ValidationError, "recovery App Store notes do not match the immutable approval"
      end

      naming = ReleaseNaming.new(
        channel: data.fetch("channel"),
        version: data.fetch("target_version"),
        build: data.fetch("canonical_build"),
        iteration: data.fetch("iteration")
      )
      unless naming.tag == tag && naming.title == data.fetch("title") &&
             naming.public_artifacts == data.fetch("artifact_names")
        raise ValidationError, "failed release identity is not canonical"
      end
    end

    def validate_github_release!(data, tag)
      commit = data.fetch("release_commit_sha")
      raise ValidationError, "failed release tag moved" unless @github.ref_sha("tags/#{tag}") == commit

      @github.validate_release_target!(
        target_sha: commit,
        protected_paths: PublishHandoff::RELEASE_PATHS
      )
      release = @github.release_by_tag(tag)
      unless release["tag_name"] == tag && release["draft"] == false && release["prerelease"] == true &&
             release["name"] == data.fetch("title") &&
             release.dig("author", "login") == PublishHandoff::RELEASE_APP_LOGIN
        raise ValidationError, "failed GitHub prerelease identity changed"
      end
      unless Array(release["assets"]).empty?
        raise ValidationError, "build-number recovery is unsafe after release assets were attached"
      end
    end

    def positive_integer(value, label)
      integer = Integer(value)
      raise ValidationError, "#{label} must be positive" unless integer.positive?

      integer
    rescue ArgumentError, TypeError
      raise ValidationError, "#{label} must be an integer"
    end
  end
end
