# frozen_string_literal: true

require "test_helper"
require "sequel_ace_release/cloud_workflow_trigger"

class CloudWorkflowTriggerTest < Minitest::Test
  TAG = "production/6.0.3-20116"

  class ReadOnlyClient
    attr_reader :reads

    def initialize(resource)
      @resource = resource
      @reads = []
    end

    def workflow(id)
      @reads << id
      @resource
    end
  end

  def source(pattern = "production/", prefix: true)
    { "isAllMatch" => false, "patterns" => [{ "pattern" => pattern, "isPrefix" => prefix }] }
  end

  def resource(overrides = {})
    {
      "id" => "workflow-id", "type" => "ciWorkflows",
      "attributes" => {
        "isEnabled" => true,
        "lastModifiedDate" => "2026-10-08T19:25:00Z",
        "tagStartCondition" => { "source" => source }
      }.merge(overrides)
    }
  end

  def inspect_resource(payload)
    client = ReadOnlyClient.new(payload)
    report = SequelAceRelease::CloudWorkflowTrigger.new(client: client).inspect(workflow_id: "workflow-id", tag: TAG)
    assert_equal ["workflow-id"], client.reads
    report
  end

  def test_matching_prefix_is_ready_and_validate_is_read_only
    client = ReadOnlyClient.new(resource)
    report = SequelAceRelease::CloudWorkflowTrigger.new(client: client).validate!(workflow_id: "workflow-id", tag: TAG)
    assert report.fetch("ready")
    assert_equal source, report.dig("automatic_tag_trigger", "source")
    assert_nil report.fetch("reason")
    assert_equal ["workflow-id"], client.reads
  end

  def test_matching_exact_and_all_tags_sources
    assert inspect_resource(resource("tagStartCondition" => { "source" => source(TAG, prefix: false) })).fetch("ready")
    assert inspect_resource(resource("tagStartCondition" => { "source" => { "isAllMatch" => true } })).fetch("ready")
  end

  def test_missing_disabled_and_manual_only_do_not_authorize_tag_creation
    [
      resource("tagStartCondition" => nil),
      resource("isEnabled" => false),
      resource("tagStartCondition" => nil, "manualTagStartCondition" => { "source" => source })
    ].each do |payload|
      report = inspect_resource(payload)
      refute report.fetch("ready")
      assert_match(/missing|disabled/, report.fetch("reason"))
      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::CloudWorkflowTrigger.new(client: ReadOnlyClient.new(payload)).validate!(workflow_id: "workflow-id", tag: TAG)
      end
      assert_equal report.fetch("reason"), error.message
    end
    manual = inspect_resource(resource("tagStartCondition" => nil, "manualTagStartCondition" => { "source" => source }))
    assert manual.dig("manual_tag_trigger", "matches_tag")
  end

  def test_patterns_are_literal_case_sensitive_exact_or_prefix_matches
    [source("beta/"), source("Production/"), source("production/*", prefix: false), source("production/*"), source("production/", prefix: false)].each do |pattern|
      report = inspect_resource(resource("tagStartCondition" => { "source" => pattern }))
      refute report.fetch("ready")
      refute report.dig("automatic_tag_trigger", "matches_tag")
      assert_includes report.fetch("reason"), "does not match"
    end
  end

  def test_file_matchers_fail_closed_and_empty_rules_are_unrestricted
    ["START_IF_ANY_FILE_MATCHES", "DO_NOT_START_IF_ALL_FILES_MATCH", "FUTURE_MODE"].each do |mode|
      condition = { "source" => source, "filesAndFoldersRule" => { "mode" => mode, "matchers" => [] } }
      assert inspect_resource(resource("tagStartCondition" => condition)).fetch("ready")
      condition["filesAndFoldersRule"]["matchers"] = [{ "fileName" => "private-secret" }]
      report = inspect_resource(resource("tagStartCondition" => condition))
      refute report.fetch("ready")
      assert_equal({ "mode" => mode, "matcher_count" => 1 }, report.dig("automatic_tag_trigger", "files_and_folders_rule"))
      assert_includes report.fetch("reason"), "restrictive file matchers"
      refute_includes JSON.generate(report), "private-secret"
    end
  end

  def test_malformed_trigger_fields_fail_closed_without_raw_errors
    [
      false, [], {}, { "source" => [] },
      { "source" => { "isAllMatch" => "true", "patterns" => [] } },
      { "source" => { "isAllMatch" => false } },
      { "source" => { "isAllMatch" => false, "patterns" => "secret" } },
      { "source" => { "isAllMatch" => true, "patterns" => [{}] } },
      { "source" => source("", prefix: true) },
      { "source" => { "isAllMatch" => false, "patterns" => [{ "pattern" => "secret", "isPrefix" => "true" }] } },
      { "source" => source, "filesAndFoldersRule" => {} },
      { "source" => source, "filesAndFoldersRule" => { "mode" => "secret", "matchers" => nil } }
    ].each do |condition|
      report = inspect_resource(resource("tagStartCondition" => condition))
      refute report.fetch("ready")
      assert_includes report.fetch("reason"), "malformed"
      refute_includes JSON.generate(report), "secret"
    end
  end

  def test_malformed_workflow_enabled_date_and_manual_trigger_fail_closed
    [nil, [], {}, resource.merge("id" => "other-id"), resource("isEnabled" => "true"), resource("lastModifiedDate" => "secret"), resource("manualTagStartCondition" => {})].each do |payload|
      report = inspect_resource(payload)
      refute report.fetch("ready")
      assert_includes report.fetch("reason"), "malformed"
      refute_includes JSON.generate(report), "secret"
    end
  end

  def test_report_allowlists_fields_and_never_includes_workflow_secrets
    payload = resource("environment" => { "TOKEN" => "private-secret" }, "name" => "private-secret")
    payload["attributes"]["tagStartCondition"]["source"]["secret"] = "private-secret"
    payload["attributes"]["tagStartCondition"]["source"]["patterns"].first["secret"] = "private-secret"
    payload["relationships"] = { "secret" => "private-secret" }
    report = inspect_resource(payload)
    assert report.fetch("ready")
    refute_includes JSON.generate(report), "private-secret"
    assert_equal %w[isAllMatch patterns], report.dig("automatic_tag_trigger", "source").keys
    assert_equal %w[pattern isPrefix], report.dig("automatic_tag_trigger", "source", "patterns").first.keys
  end

  def test_invalid_requested_identity_does_not_call_client
    client = ReadOnlyClient.new(resource)
    ["", "../private-secret"].each do |id|
      assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::CloudWorkflowTrigger.new(client: client).inspect(workflow_id: id, tag: TAG)
      end
    end
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::CloudWorkflowTrigger.new(client: client).inspect(workflow_id: "workflow-id", tag: nil)
    end
    assert_empty client.reads
  end
end
