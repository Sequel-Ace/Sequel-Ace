# frozen_string_literal: true

module SequelAceRelease
  class CloudRunStatus
    READINESS_STATES = %w[pending ready failed].freeze
    RUN_ID_PATTERN = /\A[A-Za-z0-9-]+\z/.freeze
    NOTARIZED_ARTIFACT_TYPE = "STAPLED_NOTARIZED_ARCHIVE".freeze

    def initialize(client:)
      @client = client
    end

    def readiness(workflow_id:, app_id:, version:, tag:, commit:, build: nil, run_id: nil)
      requested_run_id = run_id.to_s.empty? ? nil : run_id
      if requested_run_id && !requested_run_id.to_s.match?(RUN_ID_PATTERN)
        raise ValidationError, "requested Xcode Cloud build-run ID is malformed"
      end
      expected_build = build.nil? ? nil : positive_integer(build, "expected Production build")
      run = @client.find_cloud_run(
        workflow_id: workflow_id,
        commit: commit,
        tag: tag,
        run_id: requested_run_id
      )
      return pending("run_not_found") unless run

      unless run["id"].to_s.match?(RUN_ID_PATTERN)
        raise ValidationError, "Xcode Cloud returned a malformed build-run ID"
      end

      if expected_build
        assigned_build = positive_integer(run["number"], "assigned Production build")
        if assigned_build != expected_build
          direction = assigned_build > expected_build ? "advanced" : "regressed"
          result = run.merge(
            "readiness" => "failed",
            "reason" => "cloud_build_number_#{direction}",
            "expected_build" => expected_build,
            "assigned_build" => assigned_build
          )
          result["recovery_build"] = assigned_build + 1 if direction == "advanced"
          return result
        end
      end

      run_complete = run["execution_progress"] == "COMPLETE"
      if run_complete && run["completion_status"] != "SUCCEEDED"
        return run.merge("readiness" => "failed", "reason" => "cloud_run_failed")
      end

      cloud_builds = begin
        @client.cloud_builds_for_run(run.fetch("id"))
      rescue APIError => error
        raise unless error.message.include?("HTTP 404")

        []
      end
      matching_build = cloud_builds.find do |candidate|
        next false unless candidate["app_id"] == app_id
        next false unless candidate["version"] == version
        next false unless candidate["platform"] == "MAC_OS"
        next false if expected_build && candidate["build"] != expected_build

        true
      end
      if matching_build
        # Archive completion and export downloads can precede notarization.
        # Require Apple's stapled artifact even when the aggregate run is complete;
        # logs, xcarchives, and unstapled Developer ID exports cannot admit a verifier.
        unless downloadable_notarized_artifact?(run.fetch("id"))
          return run.merge("readiness" => "pending", "reason" => "notarized_artifact_not_ready")
        end

        return run.merge(
          "readiness" => "ready",
          "reason" => run_complete ? "exact_build_ready" : "exact_build_and_artifact_ready",
          "app_store_build_id" => matching_build.fetch("id"),
          "app_version" => matching_build.fetch("version"),
          "app_build" => matching_build.fetch("build")
        )
      end

      unless cloud_builds.empty? || !run_complete
        observed = cloud_builds.map { |candidate| candidate.slice("app_id", "version", "platform", "build") }
        raise ValidationError,
              "Xcode Cloud run does not contain the expected MAC_OS app version/build (observed: #{observed})"
      end

      reason = run_complete ? "app_store_build_not_ready" : "run_in_progress"
      run.merge("readiness" => "pending", "reason" => reason)
    end

    private

    def pending(reason)
      { "readiness" => "pending", "reason" => reason }
    end

    def downloadable_notarized_artifact?(run_id)
      @client.run_artifacts(run_id).any? do |artifact|
        artifact.dig("attributes", "fileType") == NOTARIZED_ARTIFACT_TYPE &&
          artifact.dig("attributes", "downloadUrl").to_s.start_with?("https://")
      end
    rescue APIError => error
      raise unless error.message.include?("HTTP 404")

      false
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
