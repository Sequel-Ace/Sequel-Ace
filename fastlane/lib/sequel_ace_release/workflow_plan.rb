# frozen_string_literal: true

require "base64"

module SequelAceRelease
  # A read-only adapter from the public dispatch form to the existing guarded
  # release engine. The optional SHA is an assertion, not authority to release
  # stale source. Credentials, build numbers and recovery remain internal.
  class WorkflowPlan
    INPUTS = %w[channel version app_store_notes expected_main_sha preview_only].freeze

    def initialize(planner:)
      @planner = planner
    end

    def create(inputs:, main_sha:)
      raise ValidationError, "unexpected self-service release input" unless (inputs.keys - INPUTS).empty?
      raise ValidationError, "dispatch main SHA is malformed" unless Config.valid_git_sha?(main_sha)
      expected_sha = inputs.fetch("expected_main_sha", "")
      unless expected_sha.is_a?(String) && (expected_sha.empty? ||
             (Config.valid_git_sha?(expected_sha) && expected_sha.downcase == main_sha.downcase))
        raise ValidationError, "optional main commit must match latest main at submission; leave blank to use latest main"
      end
      channel = Config.validate_channel!(inputs.fetch("channel"))
      version = Version.validate!(inputs.fetch("version"))
      preview = inputs.fetch("preview_only", false)
      unless [true, false, "true", "false"].include?(preview)
        raise ValidationError, "preview_only must be a boolean"
      end
      notes = normalize_notes(inputs.fetch("app_store_notes"))
      plan = @planner.plan(
        channel: channel, target_version: version, main_ref: main_sha,
        app_store_notes: notes
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

    private

    def normalize_notes(value)
      unless value.is_a?(String) && value.valid_encoding? && !value.include?("\0")
        raise ValidationError, "release notes must be text without NUL bytes"
      end
      # GitHub's native form has no textarea input. Pipes offer a human-readable
      # alternative; CLI/API callers can send real newlines without escaping.
      lines = value.split(/\r\n|[\r\n|]/).map(&:strip).reject(&:empty?)
      lines.map! do |line|
        # Normalize pasted Markdown, numbered lists and common rich-text bullets.
        # Require a boundary for ASCII markers so -1, C++ and version numbers
        # remain content. Repeated markers must not produce "- - Change".
        marker = /\A(?:(?:[-*+–—]|\d+[.)])(?:[[:space:]]+|\z)|[•●▪◦‣][[:space:]]*)/
        line = line.sub(marker, "").strip while line.match?(marker)
        line
      end
      if lines.empty? || lines.any? { |line| line.empty? || line.start_with?("#") }
        raise ValidationError, "enter release-note changes separated by | or newlines, without headings"
      end
      lines.map { |line| "- #{line}" }.join("\n")
    end
  end
end
