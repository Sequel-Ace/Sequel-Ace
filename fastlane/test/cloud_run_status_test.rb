# frozen_string_literal: true

require "test_helper"

class CloudRunStatusTest < Minitest::Test
  class Client
    attr_reader :find_arguments, :build_run_id

    def initialize(run:, builds: [])
      @run = run
      @builds = builds
    end

    def find_cloud_run(**arguments)
      @find_arguments = arguments
      @run
    end

    def cloud_builds_for_run(run_id)
      @build_run_id = run_id
      raise @builds if @builds.is_a?(Exception)

      @builds
    end
  end

  def test_reports_a_missing_exact_run_as_pending_without_sleeping
    client = Client.new(run: nil)

    result = inspect(client)

    assert_equal "pending", result.fetch("readiness")
    assert_equal "run_not_found", result.fetch("reason")
    assert_nil client.build_run_id
    assert_equal "workflow-id", client.find_arguments.fetch(:workflow_id)
    assert_equal "production/5.3.2-20105", client.find_arguments.fetch(:tag)
  end

  def test_reports_an_in_progress_run_as_pending_without_reading_builds
    client = Client.new(run: cloud_run("RUNNING", nil))

    result = inspect(client)

    assert_equal "pending", result.fetch("readiness")
    assert_equal "run_in_progress", result.fetch("reason")
    assert_equal "run-id", result.fetch("id")
    assert_nil client.build_run_id
  end

  def test_reports_a_completed_unsuccessful_run_as_failed
    client = Client.new(run: cloud_run("COMPLETE", "FAILED"))

    result = inspect(client)

    assert_equal "failed", result.fetch("readiness")
    assert_equal "cloud_run_failed", result.fetch("reason")
    assert_equal "FAILED", result.fetch("completion_status")
    assert_nil client.build_run_id
  end

  def test_reports_ready_only_after_the_exact_app_build_is_related
    client = Client.new(
      run: cloud_run("COMPLETE", "SUCCEEDED"),
      builds: [{
        "id" => "app-store-build-id",
        "app_id" => "1518036000",
        "version" => "5.3.2",
        "platform" => "MAC_OS",
        "build" => 20_105
      }]
    )

    result = inspect(client)

    assert_equal "ready", result.fetch("readiness")
    assert_equal "exact_build_ready", result.fetch("reason")
    assert_equal "app-store-build-id", result.fetch("app_store_build_id")
    assert_equal 20_105, result.fetch("app_build")
    assert_equal "run-id", client.build_run_id
  end

  def test_keeps_a_succeeded_run_pending_while_its_app_store_build_is_unavailable
    client = Client.new(run: cloud_run("COMPLETE", "SUCCEEDED"), builds: [])

    result = inspect(client)

    assert_equal "pending", result.fetch("readiness")
    assert_equal "app_store_build_not_ready", result.fetch("reason")
  end

  def test_treats_a_temporarily_missing_build_relationship_as_pending
    client = Client.new(
      run: cloud_run("COMPLETE", "SUCCEEDED"),
      builds: SequelAceRelease::APIError.new("App Store Connect API returned HTTP 404")
    )

    result = inspect(client)

    assert_equal "pending", result.fetch("readiness")
    assert_equal "app_store_build_not_ready", result.fetch("reason")
  end

  def test_rejects_a_completed_run_related_to_the_wrong_build
    client = Client.new(
      run: cloud_run("COMPLETE", "SUCCEEDED"),
      builds: [{
        "id" => "wrong-build-id",
        "app_id" => "1518036000",
        "version" => "5.3.2",
        "platform" => "MAC_OS",
        "build" => 20_106
      }]
    )

    error = assert_raises(SequelAceRelease::ValidationError) { inspect(client) }
    assert_includes error.message, "does not contain the expected MAC_OS app version/build"
  end

  def test_rejects_a_completed_run_related_to_the_wrong_platform
    client = Client.new(
      run: cloud_run("COMPLETE", "SUCCEEDED"),
      builds: [{
        "id" => "ios-build-id",
        "app_id" => "1518036000",
        "version" => "5.3.2",
        "platform" => "IOS",
        "build" => 20_105
      }]
    )

    error = assert_raises(SequelAceRelease::ValidationError) { inspect(client) }

    assert_includes error.message, "MAC_OS"
  end

  private

  def inspect(client)
    SequelAceRelease::CloudRunStatus.new(client: client).inspect(
      workflow_id: "workflow-id",
      app_id: "1518036000",
      version: "5.3.2",
      tag: "production/5.3.2-20105",
      build: 20_105,
      commit: "a" * 40,
      run_id: "run-id"
    )
  end

  def cloud_run(progress, completion)
    {
      "id" => "run-id",
      "number" => 20_105,
      "execution_progress" => progress,
      "completion_status" => completion,
      "workflow_id" => "workflow-id",
      "git_reference" => "production/5.3.2-20105",
      "source_commit" => "a" * 40
    }
  end
end
