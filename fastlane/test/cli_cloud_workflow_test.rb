# frozen_string_literal: true
require "test_helper"
require "yaml"
require "open3"

class CLICloudWorkflowTest < Minitest::Test
  def run_cli(arguments, enabled: true, condition: true)
    client = Object.new
    client.define_singleton_method(:workflow) do |id|
      raise "wrong workflow" unless id == "production-workflow"
      { "id" => id, "attributes" => {
        "isEnabled" => enabled,
        "tagStartCondition" => condition ? { "source" => { "isAllMatch" => false,
          "patterns" => [{ "pattern" => "production/", "isPrefix" => true }] } } : nil
      } }
    end
    cli = Class.new(SequelAceRelease::CLI) do
      define_method(:app_store_client) { client }
    end
    out, err = StringIO.new, StringIO.new
    status = cli.run(arguments, out: out, err: err, env: {})
    [status, out.string, err.string]
  end

  def args
    ["cloud-workflow-status", "--workflow-id", "production-workflow", "--tag", "production/6.0.3-20116"]
  end

  def test_read_only_diagnostics_can_report_manual_only_without_failure
    status, output, error = run_cli(args, condition: false)
    assert_equal 0, status, error
    refute JSON.parse(output).fetch("ready")
  end

  def test_preflight_rejects_missing_automatic_condition_and_disabled_workflow
    [{ condition: false }, { enabled: false }].each do |options|
      status, _output, error = run_cli(args + ["--require-automatic"], **options)
      refute_equal 0, status
      refute_empty error
    end
  end

  def test_preflight_accepts_matching_tag_without_mutation_api
    status, output, error = run_cli(args + ["--require-automatic"])
    assert_equal 0, status, error
    assert JSON.parse(output).fetch("ready")
  end

  def test_release_gates_preparation_and_both_tag_publishers_with_read_only_command
    path = File.expand_path("../../.github/workflows/release.yml", __dir__)
    workflow = YAML.load_file(path)
    steps = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    first = steps.index { |step| step["name"] == "Reconcile the authoritative Production Cloud build" }
    manifest = steps.index { |step| step["name"] == "Create the initial release manifest" }
    gate = steps.index { |step| step["name"] == "Require automatic Cloud start immediately before creating the tag" }
    assert_operator first, :<, manifest
    assert_includes steps[first].fetch("run"), "trigger_args=(--require-automatic)"
    %w[prerelease_user prerelease_app].each do |id|
      assert_operator gate, :<, steps.index { |step| step["id"] == id }
    end
    command = steps[gate].fetch("run")
    assert_includes command, "cloud-workflow-status"
    assert_includes command, "trigger_args=(--require-automatic)"
    refute_match(/retry-alpha|start_cloud_run|POST|PATCH/, command)
    assert_includes File.read(path), "cloud-trigger-before-tag.json release-archive/"
  end

  def test_existing_tag_recovery_does_not_require_a_new_automatic_event
    workflow = YAML.load_file(File.expand_path("../../.github/workflows/release.yml", __dir__))
    steps = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    names = ["Reconcile the authoritative Production Cloud build", "Require automatic Cloud start immediately before creating the tag"]
    names.each do |name|
      run = steps.find { |step| step["name"] == name }.fetch("run")
      # Execute the actual shell selection block for both recovery and a fresh
      # release; later changes must not accidentally turn recovery into a gate.
      block = run[/trigger_args=\(--require-automatic\).*?\nfi/m]
      refute_nil block
      variable = name.start_with?("Reconcile") ? "reconciliation_reason" : "RECONCILIATION_REASON"
      %w[resume_after_tag advance].each do |reason|
        script = block + "\nprintf \"%s\" \"${trigger_args[*]}\""
        out, err, status = Open3.capture3({ variable => reason }, "bash", "-c", script)
        assert status.success?, err
        assert_equal(reason == "resume_after_tag" ? "" : "--require-automatic", out)
      end
    end
    status, output, error = run_cli(args, enabled: false)
    assert_equal 0, status, error
    refute JSON.parse(output).fetch("ready")
  end

  def test_status_collects_diagnostics_without_changing_cloud_configuration
    workflow = YAML.load_file(File.expand_path("../../.github/workflows/release_status.yml", __dir__))
    steps = workflow.fetch("jobs").fetch("inspect").fetch("steps")
    run = steps.find { |step| step["name"] == "Read archived handoff and App Store Connect API" }.fetch("run")
    assert_includes run, "cloud-workflow-status"
    assert_includes run, 'report["cloud_workflow"]'
    refute_includes run, "--require-automatic"
    refute_match(/start_cloud_run|POST|PATCH/, run)
    embedded = run.scan(/<<'RUBY'\n(.*?)^RUBY$/m).flatten
    embedded.each do |script|
      _out, err, status = Open3.capture3(RbConfig.ruby, "-c", stdin_data: script)
      assert status.success?, err
    end
  end
end
