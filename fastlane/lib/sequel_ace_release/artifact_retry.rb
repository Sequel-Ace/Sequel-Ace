# frozen_string_literal: true

require "digest"

module SequelAceRelease
  # Explicit recovery of an inspected, pre-publication failure using the same
  # successful Cloud run. It never creates a build or relaxes artifact checks.
  class ArtifactRetry
    def initialize(github:, client:, cloud: CloudRunStatus.new(client: client))
      @github, @client, @cloud = github, client, cloud
    end

    def prepare(manifest_bytes:, expected_digest:, tag:, commit:, run_id:, workflow_id:, notes:, actor:, workflow_url:)
      unless expected_digest.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.hexdigest(manifest_bytes) == expected_digest
        raise ValidationError, "preserved failure manifest changed"
      end
      raise ValidationError, "unauthorized artifact retry actor" unless %w[Jason-Morcos Kaspik].include?(actor)
      original = Manifest.new(JSON.parse(manifest_bytes))
      data = original.to_h
      unless data["state"] == "failed" && data["channel"] == "production" &&
             data["tag"] == tag && data["release_commit_sha"] == commit &&
             data.fetch("verification").empty? && data.fetch("asc_ids").empty? &&
             data["failure"].is_a?(Hash) && !data["failure"].empty?
        raise ValidationError, "retry requires an exact failed Production handoff before verification or submission"
      end
      unless run_id.to_s.match?(CloudRunStatus::RUN_ID_PATTERN)
        raise ValidationError, "artifact retry requires an exact Cloud run"
      end
      archived_run = data.fetch("cloud_build_ids")["production"]
      if archived_run && archived_run != run_id
        raise ValidationError, "requested Cloud run differs from archived run"
      end
      PublishHandoff.new(github: @github).validate(manifest: original, tag: tag, app_store_notes: notes)
      unless @github.release_by_tag(tag).fetch("assets").empty?
        raise ValidationError, "artifact retry requires no public assets"
      end
      if @client.app_store_version(app_id: Config::PRODUCTION_APP_ID, version: data.fetch("target_version"))
        raise ValidationError, "artifact retry cannot reset an existing App Store version"
      end
      cloud = @cloud.readiness(
        workflow_id: workflow_id, app_id: Config::PRODUCTION_APP_ID,
        version: data.fetch("target_version"), tag: tag, commit: commit,
        build: data.fetch("canonical_build"), run_id: run_id
      )
      unless cloud["id"] == run_id && cloud["readiness"] == "ready" &&
             cloud["execution_progress"] == "COMPLETE" && cloud["completion_status"] == "SUCCEEDED"
        raise ValidationError, "exact Cloud run must have succeeded and expose its stapled notarized artifact"
      end
      history = data.fetch("artifact_retry_history", [])
      raise ValidationError, "artifact retry history is malformed" unless history.is_a?(Array)
      original.with(
        "state" => "cloud_running",
        "cloud_build_ids" => data.fetch("cloud_build_ids").merge("production" => run_id),
        "artifact_retry_history" => history + [{
          "previous_manifest_sha256" => expected_digest, "previous_failure" => data.fetch("failure"),
          "actor" => actor, "workflow_url" => workflow_url, "cloud_run_id" => run_id,
          "authorized_at" => Time.now.utc.iso8601
        }]
      )
    end
  end
end
