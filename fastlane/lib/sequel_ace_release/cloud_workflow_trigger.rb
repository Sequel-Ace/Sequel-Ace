# frozen_string_literal: true

require "time"

module SequelAceRelease
  # A manual start permission cannot prove that pushing a release tag starts a run.
  class CloudWorkflowTrigger
    def initialize(client:)
      @client = client
    end

    def inspect(workflow_id:, tag:)
      unless workflow_id.is_a?(String) && workflow_id.match?(/\A[A-Za-z0-9-]+\z/) && tag.is_a?(String) && !tag.empty?
        raise ValidationError, "A workflow ID and nonempty release tag are required to inspect Cloud triggers"
      end

      resource = @client.workflow(workflow_id)
      attributes = resource.is_a?(Hash) && resource["attributes"].is_a?(Hash) ? resource["attributes"] : {}
      automatic, automatic_error = trigger(attributes["tagStartCondition"], tag, files: true)
      manual, manual_error = trigger(attributes["manualTagStartCondition"], tag, files: false)
      enabled = boolean?(attributes["isEnabled"]) ? attributes["isEnabled"] : nil
      date = attributes["lastModifiedDate"]
      valid_date = date.nil? || (date.is_a?(String) && iso8601?(date))
      reason = if !resource.is_a?(Hash) || resource["id"] != workflow_id || !resource["attributes"].is_a?(Hash)
        "Cloud workflow response is missing or malformed; read the configured workflow before creating a release tag"
      elsif enabled.nil?
        "Cloud workflow enabled state is missing or malformed; verify it before creating a release tag"
      elsif !enabled
        "Cloud workflow is disabled; enable it and verify the automatic tag trigger before creating a release tag"
      elsif !valid_date
        "Cloud workflow modification date is malformed; read the workflow again before creating a release tag"
      elsif automatic_error
        automatic_error
      elsif !automatic["configured"]
        "Cloud automatic tag trigger is missing; configure it for the release tag before creating the tag"
      elsif !automatic["matches_tag"]
        "Cloud automatic tag trigger does not match the release tag; correct its exact or prefix pattern before creating the tag"
      elsif automatic.dig("files_and_folders_rule", "matcher_count").to_i.positive?
        "Cloud automatic tag trigger has restrictive file matchers; remove the restriction before creating a release tag"
      elsif manual_error
        manual_error
      end
      {
        "workflow_id" => workflow_id,
        "enabled" => enabled,
        "last_modified_date" => valid_date ? date : nil,
        "automatic_tag_trigger" => automatic,
        "manual_tag_trigger" => manual,
        "ready" => reason.nil?,
        "reason" => reason
      }
    end

    def validate!(workflow_id:, tag:)
      report = inspect(workflow_id: workflow_id, tag: tag)
      raise ValidationError, report.fetch("reason") unless report.fetch("ready")

      report
    end

    private

    def trigger(condition, tag, files:)
      report = { "configured" => !condition.nil?, "matches_tag" => false, "source" => nil }
      report["files_and_folders_rule"] = { "mode" => nil, "matcher_count" => 0 } if files
      return [report, nil] if condition.nil?

      label = files ? "automatic" : "manual"
      malformed = "Cloud #{label} tag trigger is malformed; verify its source and file rules before creating a release tag"
      return [report, malformed] unless condition.is_a?(Hash)

      source = condition["source"]
      return [report, malformed] unless source.is_a?(Hash) && boolean?(source["isAllMatch"])

      patterns = source["patterns"]
      patterns = [] if patterns.nil? && source["isAllMatch"]
      return [report, malformed] unless patterns.is_a?(Array) && patterns.all? { |pattern| valid_pattern?(pattern) }

      report["source"] = {
        "isAllMatch" => source["isAllMatch"],
        "patterns" => patterns.map { |pattern| { "pattern" => pattern["pattern"], "isPrefix" => pattern["isPrefix"] } }
      }
      report["matches_tag"] = source["isAllMatch"] || patterns.any? do |pattern|
        pattern["isPrefix"] ? tag.start_with?(pattern["pattern"]) : tag == pattern["pattern"]
      end
      if files && !condition["filesAndFoldersRule"].nil?
        rule = condition["filesAndFoldersRule"]
        return [report, malformed] unless rule.is_a?(Hash) && rule["mode"].is_a?(String) && !rule["mode"].empty? && rule["matchers"].is_a?(Array)

        report["files_and_folders_rule"] = { "mode" => rule["mode"], "matcher_count" => rule["matchers"].length }
      end
      [report, nil]
    end

    def valid_pattern?(pattern)
      pattern.is_a?(Hash) && pattern["pattern"].is_a?(String) && !pattern["pattern"].empty? && boolean?(pattern["isPrefix"])
    end

    def boolean?(value)
      value == true || value == false
    end

    def iso8601?(value)
      Time.iso8601(value)
      true
    rescue ArgumentError
      false
    end
  end
end
