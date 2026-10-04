# frozen_string_literal: true

module SequelAceRelease
  class SubmissionReconciler
    SUBMITTED_STATES = %w[
      WAITING_FOR_REVIEW IN_REVIEW PENDING_APPLE_RELEASE
      PENDING_DEVELOPER_RELEASE PROCESSING_FOR_DISTRIBUTION
      READY_FOR_DISTRIBUTION ACCEPTED
    ].freeze

    def initialize(
      client:,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      sleeper: ->(seconds) { sleep(seconds) }
    )
      @client = client
      @clock = clock
      @sleeper = sleeper
    end

    def reconcile(manifest, timeout_seconds: 0, interval_seconds: 15)
      timeout = numeric_duration(timeout_seconds, "submission reconciliation timeout", allow_zero: true)
      interval = numeric_duration(interval_seconds, "submission reconciliation poll interval", allow_zero: false)
      return reconcile_once(manifest) if timeout.zero?

      deadline = @clock.call + timeout
      attempts = 0
      loop do
        attempts += 1
        result = reconcile_once(manifest)
        return result.merge("poll_attempts" => attempts, "polling_timed_out" => false) if result.fetch("submitted")

        remaining = deadline - @clock.call
        if remaining <= 0
          return result.merge("poll_attempts" => attempts, "polling_timed_out" => true)
        end

        @sleeper.call([interval, remaining].min)
      end
    end

    private

    def reconcile_once(manifest)
      data = manifest.to_h
      raise ValidationError, "App Store submission reconciliation is production-only" unless data["channel"] == "production"

      version = @client.app_store_version(
        app_id: Config::PRODUCTION_APP_ID,
        version: data.fetch("target_version")
      )
      return not_submitted("version_not_found") unless version

      state = MetadataValidator.app_version_state(version)
      return not_submitted("state_not_submitted", version: version, state: state) unless SUBMITTED_STATES.include?(state)

      selected_build = @client.selected_build(version_id: version.fetch("id"))
      return not_submitted("selected_build_not_found", version: version, state: state) unless selected_build

      actual_build = selected_build.dig("attributes", "version").to_s
      expected_build = data.fetch("canonical_build").to_s
      unless actual_build == expected_build
        raise ValidationError, "submitted App Store build #{actual_build} does not match #{expected_build}"
      end

      {
        "submitted" => true,
        "reason" => "exact_submission_confirmed",
        "version_id" => version.fetch("id"),
        "build_id" => selected_build.fetch("id"),
        "app_store_state" => state
      }
    end

    def numeric_duration(value, label, allow_zero:)
      duration = Float(value)
      valid = duration.finite? && (allow_zero ? !duration.negative? : duration.positive?)
      raise ValidationError, "#{label} must be #{allow_zero ? 'nonnegative' : 'positive'}" unless valid

      duration
    rescue ArgumentError, TypeError
      raise ValidationError, "#{label} must be numeric"
    end

    def not_submitted(reason, version: nil, state: nil)
      {
        "submitted" => false,
        "reason" => reason,
        "version_id" => version&.fetch("id", nil),
        "app_store_state" => state
      }.compact
    end
  end
end
