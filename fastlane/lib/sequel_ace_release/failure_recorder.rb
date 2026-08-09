# frozen_string_literal: true

module SequelAceRelease
  class FailureRecorder
    FINALIZABLE_STATES = %w[submitted live].freeze
    DURABLE_BETA_STATES = %w[archived].freeze
    SUBMISSION_FIELDS = %w[
      version_id build_id app_store_state scheduled_release_at phased_release_state
    ].freeze
    Result = Struct.new(:manifest, :preserve_release_body, :submission_confirmed, keyword_init: true) do
      def to_h
        {
          "state" => manifest.to_h.fetch("state"),
          "preserve_release_body" => preserve_release_body,
          "submission_confirmed" => submission_confirmed,
          "failure" => manifest.to_h.fetch("failure")
        }
      end
    end

    def record(manifest:, workflow_url:, submission: nil)
      raise ValidationError, "failure workflow URL is required" if workflow_url.to_s.empty?

      current = manifest.to_h
      target_state = current.fetch("state")
      updates = {
        "failure" => { "workflow_url" => workflow_url }
      }
      if submission
        validate_submission!(current, submission)
        updates["asc_ids"] = submission.slice(*SUBMISSION_FIELDS)
        target_state = "submitted" unless target_state == "live"
      elsif current.fetch("channel") == "beta" && DURABLE_BETA_STATES.include?(target_state)
        # Artifact recovery is already durable. Record the later workflow
        # failure without erasing the successful archived checkpoint.
        target_state = "archived"
      elsif !FINALIZABLE_STATES.include?(target_state)
        target_state = "failed"
      end
      updates["state"] = target_state
      updated = manifest.with(updates)

      Result.new(
        manifest: updated,
        preserve_release_body: FINALIZABLE_STATES.include?(target_state),
        submission_confirmed: !submission.nil?
      )
    end

    private

    def validate_submission!(manifest, submission)
      raise ValidationError, "App Store submission evidence is production-only" unless manifest["channel"] == "production"
      if submission.key?("submitted") && submission["submitted"] != true
        raise ValidationError, "App Store submission evidence is not confirmed"
      end

      missing = %w[version_id build_id app_store_state].select { |key| submission[key].to_s.empty? }
      unless missing.empty?
        raise ValidationError, "App Store submission evidence is missing: #{missing.join(', ')}"
      end
      unless SubmissionReconciler::SUBMITTED_STATES.include?(submission["app_store_state"])
        raise ValidationError, "App Store submission state is not finalizable: #{submission['app_store_state']}"
      end
    end
  end
end
