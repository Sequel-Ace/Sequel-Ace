# frozen_string_literal: true

require "base64"

module SequelAceRelease
  # A read-only adapter from the public dispatch form to the existing guarded
  # release engine. No credentials, build numbers, refs, or recovery authority
  # can be supplied through this form.
  class WorkflowPlan
    INPUTS = %w[channel version app_store_notes github_release_notes preview_only].freeze

    def initialize(planner:)
      @planner = planner
    end

    def create(inputs:, main_sha:)
      raise ValidationError, "unexpected self-service release input" unless (inputs.keys - INPUTS).empty?
      raise ValidationError, "dispatch main SHA is malformed" unless Config.valid_git_sha?(main_sha)
      channel = Config.validate_channel!(inputs.fetch("channel"))
      version = Version.validate!(inputs.fetch("version"))
      preview = inputs.fetch("preview_only", false)
      unless [true, false, "true", "false"].include?(preview)
        raise ValidationError, "preview_only must be a boolean"
      end
      notes = inputs.fetch("app_store_notes")
      unless notes.is_a?(String) && notes.valid_encoding? && !notes.strip.empty? &&
             !notes.include?("\0") && notes.lines.reject { |line| line.strip.empty? }.all? { |line| line.start_with?("- ") }
        raise ValidationError, "customer-facing notes must be nonempty '- ' bullets, without headings or NUL bytes"
      end
      body = inputs.fetch("github_release_notes", "")
      raise ValidationError, "GitHub release notes must be text" unless body.is_a?(String)
      plan = @planner.plan(
        channel: channel, target_version: version, main_ref: main_sha,
        app_store_notes: notes, github_release_body: body.empty? ? nil : body
      )
      approval = Approval.from_hash(plan.fetch("approval"))
      approval.verify!(plan.fetch("approval").fetch("sha256"))
      unless approval.payload.values_at("channel", "target_version", "main_sha") == [channel, version, main_sha.downcase]
        raise IntegrityError, "planner changed the requested release identity"
      end
      dispatch = {
        "mode" => "start", "channel" => channel, "version" => version,
        "expected_main_sha" => approval.payload.fetch("main_sha"),
        "previous_tag" => approval.payload.fetch("previous_tag"),
        "app_store_notes_b64" => Base64.strict_encode64(approval.payload.fetch("app_store_notes")),
        "github_release_body_b64" => Base64.strict_encode64(plan.fetch("github_release_body")),
        "approval_sha256" => approval.sha256,
        "confirmation" => "RELEASE #{channel} #{version}"
      }
      # Leave headroom below GitHub's 65,535-character dispatch payload limit.
      raise ValidationError, "encoded release notes exceed the dispatch payload budget" if JSON.generate(dispatch).bytesize > 60_000

      plan.merge("dispatch_inputs" => dispatch, "preview_only" => [true, "true"].include?(preview))
    end
  end
end
