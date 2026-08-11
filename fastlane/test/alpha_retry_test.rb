# frozen_string_literal: true

require "test_helper"

class AlphaRetryTest < Minitest::Test
  class AppStore
    attr_reader :started_reference

    def initialize(failed:, latest:)
      @failed = failed
      @latest = latest
    end

    def build_run(id)
      raise "wrong failed run" unless id == @failed.fetch("id")

      @failed
    end

    def find_cloud_run(workflow_id:, commit:, tag:)
      raise "wrong workflow" unless workflow_id == @failed.fetch("workflow_id")
      raise "wrong commit" unless commit == "d" * 40
      raise "wrong tag" unless tag == "beta/5.3.2-20105"

      @latest
    end

    def start_cloud_run(workflow_id:, git_reference_id:)
      raise "wrong workflow" unless workflow_id == @failed.fetch("workflow_id")

      @started_reference = git_reference_id
      { "id" => "retry-c" }
    end
  end

  def test_an_exact_newer_failed_run_can_be_authorized_after_an_older_archive_was_preserved
    app_store = AppStore.new(failed: failed_run("failed-b"), latest: failed_run("failed-b"))
    output = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: StringIO.new, env: {})

    status = cli.stub(:app_store_client, app_store) do
      cli.run(arguments("failed-b"))
    end

    assert_equal 0, status
    assert_equal "reference-id", app_store.started_reference
    assert_equal "retry-c", JSON.parse(output.string).fetch("id")
  end

  def test_a_different_newer_failed_run_requires_its_own_authorization
    app_store = AppStore.new(failed: failed_run("failed-a"), latest: failed_run("failed-b"))
    error = StringIO.new
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: error, env: {})

    status = cli.stub(:app_store_client, app_store) do
      cli.run(arguments("failed-a"))
    end

    assert_equal 1, status
    assert_includes error.string, "authorize that exact run ID"
    assert_nil app_store.started_reference
  end

  private

  def arguments(failed_id)
    [
      "retry-alpha",
      "--failed-run-id", failed_id,
      "--workflow-id", "alpha-workflow",
      "--tag", "beta/5.3.2-20105",
      "--commit", "d" * 40
    ]
  end

  def failed_run(id)
    {
      "id" => id,
      "workflow_id" => "alpha-workflow",
      "git_reference" => "beta/5.3.2-20105",
      "git_reference_id" => "reference-id",
      "source_commit" => "d" * 40,
      "execution_progress" => "COMPLETE",
      "completion_status" => "FAILED"
    }
  end
end
