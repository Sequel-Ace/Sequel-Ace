# frozen_string_literal: true

module SequelAceRelease
  class SubmissionReconciler
    SUBMITTED_STATES = %w[
      WAITING_FOR_REVIEW IN_REVIEW PENDING_APPLE_RELEASE
      PENDING_DEVELOPER_RELEASE PROCESSING_FOR_DISTRIBUTION
      READY_FOR_DISTRIBUTION ACCEPTED
    ].freeze

    def initialize(client:)
      @client = client
    end

    def reconcile(manifest)
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
      raise ValidationError, "submitted App Store version has no selected build" unless selected_build

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

    private

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
