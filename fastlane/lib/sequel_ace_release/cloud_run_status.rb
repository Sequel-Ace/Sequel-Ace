# frozen_string_literal: true

module SequelAceRelease
  class CloudRunStatus
    READINESS_STATES = %w[pending ready failed].freeze

    def initialize(client:)
      @client = client
    end

    def inspect(workflow_id:, app_id:, version:, tag:, commit:, build: nil, run_id: nil)
      run = @client.find_cloud_run(
        workflow_id: workflow_id,
        build: build,
        commit: commit,
        tag: tag,
        run_id: run_id
      )
      return pending("run_not_found") unless run

      unless run["execution_progress"] == "COMPLETE"
        return run.merge("readiness" => "pending", "reason" => "run_in_progress")
      end

      unless run["completion_status"] == "SUCCEEDED"
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
        next false if build && candidate["build"] != build

        true
      end
      if matching_build
        return run.merge(
          "readiness" => "ready",
          "reason" => "exact_build_ready",
          "app_store_build_id" => matching_build.fetch("id"),
          "app_version" => matching_build.fetch("version"),
          "app_build" => matching_build.fetch("build")
        )
      end

      unless cloud_builds.empty?
        observed = cloud_builds.map { |candidate| candidate.slice("app_id", "version", "platform", "build") }
        raise ValidationError,
              "Xcode Cloud run does not contain the expected MAC_OS app version/build (observed: #{observed})"
      end

      run.merge("readiness" => "pending", "reason" => "app_store_build_not_ready")
    end

    private

    def pending(reason)
      { "readiness" => "pending", "reason" => reason }
    end
  end
end
