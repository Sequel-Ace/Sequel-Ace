# frozen_string_literal: true

module SequelAceRelease
  # Read-only operations report. Never serialize Apple's raw responses: they
  # include review credentials and expiring artifact download URLs.
  class ReleaseStatus
    def initialize(client:, production_workflow_id: nil)
      @client = client
      @production_workflow_id = production_workflow_id
    end

    def inspect(manifest:, app_store_notes:)
      data = manifest.to_h
      result = {
        "tag" => data.fetch("tag"),
        "version" => data.fetch("target_version"),
        "build" => data.fetch("canonical_build"),
        "handoff_state" => data.fetch("state"),
        "artifact_owner" => "release_publish.yml",
        "next_action" => next_action(data)
      }
      if %w[cloud_running failed].include?(data.fetch("state"))
        if @production_workflow_id.to_s.empty?
          result["cloud"] = { "queried" => false, "reason" => "production_workflow_id_not_configured" }
        else
          cloud = CloudRunStatus.new(client: @client).readiness(
            workflow_id: @production_workflow_id, app_id: Config::PRODUCTION_APP_ID,
            version: data.fetch("target_version"), tag: data.fetch("tag"),
            commit: data.fetch("release_commit_sha"), build: data.fetch("canonical_build"),
            run_id: data.fetch("cloud_build_ids").fetch("production", nil)
          )
          result["cloud"] = cloud.slice("id", "number", "readiness", "reason", "app_build", "execution_progress", "completion_status").merge("queried" => true)
        end
      end
      return result.merge("app_store" => { "required" => false }) if data.fetch("channel") == "beta"

      version = @client.app_store_version(app_id: Config::PRODUCTION_APP_ID, version: data.fetch("target_version"))
      unless version
        return result.merge(
          "app_store" => { "exists" => false, "submitted" => false },
          "next_action" => "#{result.fetch('next_action')}; App Store version has not been created"
        )
      end

      begin
        snapshot = @client.metadata_snapshot(app_id: Config::PRODUCTION_APP_ID, version: data.fetch("target_version"))
      rescue ValidationError
        return result.merge(
          "next_action" => "App Store metadata is incomplete; publisher owns staging and validation",
          "app_store" => { "exists" => true, "metadata_valid" => false, "submitted" => false,
                           "state" => MetadataValidator.app_version_state(version) }
        )
      end
      state = MetadataValidator.app_version_state(snapshot.fetch("version"))
      metadata_valid = true
      metadata_error = nil
      begin
        MetadataValidator.new.validate!(
          snapshot: snapshot, expected_build: data.fetch("canonical_build"), expected_notes: app_store_notes,
          require_live: state == "READY_FOR_DISTRIBUTION",
          minimum_release_time: Time.at(0).utc
        )
      rescue ValidationError => error
        metadata_valid = false
        metadata_error = error.message
      end
      exact_build = snapshot.dig("selected_build", "attributes", "version").to_s == data.fetch("canonical_build").to_s
      submitted = exact_build && SubmissionReconciler::SUBMITTED_STATES.include?(state)
      result["app_store"] = {
        "exists" => true,
        "version_id" => snapshot.fetch("version").fetch("id"),
        "state" => state,
        "selected_build" => snapshot.dig("selected_build", "attributes", "version"),
        "submitted" => submitted,
        "metadata_valid" => metadata_valid,
        "metadata_error" => metadata_error,
        "scheduled_release_at" => snapshot.dig("version", "attributes", "earliestReleaseDate"),
        "phased_release_state" => snapshot.dig("phased_release", "attributes", "phasedReleaseState")
      }.compact
      result["next_action"] = "Reconcile App Store metadata before claiming release completion" unless metadata_valid
      result["next_action"] = "App Store submission confirmed; finalizer owns public-release promotion" if submitted && metadata_valid
      result
    end

    private

    def next_action(data)
      case data.fetch("state")
      when "cloud_running"
        "Inspect exact Cloud run and downloadable notarized resource through the ASC API"
      when "failed"
        "Inspect failure evidence and exact Cloud readiness; a successful existing Production build may use release_artifact_retry.yml"
      when "artifacts_verified"
        "Inspect github-public-assets-status; use the verified GHCR ZIP, do not rebuild or re-download Cloud artifacts"
      when "archived"
        data.fetch("channel") == "production" ? "Publisher owns App Store metadata and submission; check API readback before retrying" : "Beta artifact publication complete"
      when "submitted", "finalizing", "live"
        "Read App Store state; do not dispatch another artifact publisher"
      else
        "Inspect the exact handoff and failure evidence before recovery"
      end
    end
  end
end
