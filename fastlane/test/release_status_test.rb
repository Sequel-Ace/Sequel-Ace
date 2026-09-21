# frozen_string_literal: true

require "test_helper"

class ReleaseStatusTest < Minitest::Test
  include ReleaseTestHelpers

  # Deliberately exposes no mutation API and no Cloud download API.
  Client = Struct.new(:snapshot) do
    def app_store_version(**)
      snapshot && snapshot.fetch("version")
    end

    def metadata_snapshot(**)
      snapshot
    end
  end

  def report(snapshot, state: "submitted", channel: "production")
    manifest = Struct.new(:to_h).new({
      "tag" => "#{channel}/5.3.2-20105", "target_version" => "5.3.2",
      "canonical_build" => 20_105, "state" => state, "channel" => channel
    })
    SequelAceRelease::ReleaseStatus.new(client: Client.new(snapshot)).inspect(
      manifest: manifest, app_store_notes: "A focused release note."
    )
  end

  def test_reports_missing_version_instead_of_claiming_submission_from_manifest
    result = report(nil)
    assert_equal false, result.dig("app_store", "exists")
    assert_equal false, result.dig("app_store", "submitted")
  end

  def test_verifies_exact_build_metadata_and_submission_without_leaking_raw_data
    snapshot = metadata_snapshot(state: "WAITING_FOR_REVIEW")
    snapshot["review_detail"]["attributes"].merge!("demoAccountName" => "private-user", "demoAccountPassword" => "private-password")
    snapshot["downloadUrl"] = "https://private.invalid/signed-token"
    result = report(snapshot)
    assert result.dig("app_store", "metadata_valid")
    assert result.dig("app_store", "submitted")
    assert_equal "2026-08-12T16:00:00Z", result.dig("app_store", "scheduled_release_at")
    %w[private-user private-password signed-token release@example.invalid].each do |secret|
      refute_includes JSON.generate(result), secret
    end
  end

  def test_wrong_build_does_not_count_as_submission
    result = report(metadata_snapshot(build: 20_104, state: "WAITING_FOR_REVIEW"))
    refute result.dig("app_store", "submitted")
    refute result.dig("app_store", "metadata_valid")
  end

  def test_detects_release_notes_drift
    snapshot = metadata_snapshot(state: "WAITING_FOR_REVIEW")
    snapshot["localization"]["attributes"]["whatsNew"] = "Wrong notes"
    result = report(snapshot)
    refute result.dig("app_store", "metadata_valid")
    assert_includes result.dig("app_store", "metadata_error"), "approved notes"
  end

  def test_verified_artifacts_direct_operator_to_existing_archive_not_cloud_wait
    result = report(nil, state: "artifacts_verified")
    assert_includes result.fetch("next_action"), "verified GHCR ZIP"
    assert_equal "release_publish.yml", result.fetch("artifact_owner")
  end

  def test_beta_does_not_query_production_apple_metadata
    result = report(nil, state: "archived", channel: "beta")
    assert_equal({ "required" => false }, result.fetch("app_store"))
    assert_includes result.fetch("next_action"), "complete"
  end

  def test_running_handoff_queries_exact_cloud_run_and_does_not_emit_signed_urls
    client = Client.new(nil)
    client.define_singleton_method(:find_cloud_run) do |**args|
      raise unless args == { workflow_id: "workflow", commit: "a" * 40, tag: "production/5.3.2-20105", run_id: "run-id" }
      { "id" => "run-id", "number" => 20_105, "execution_progress" => "RUNNING", "downloadUrl" => "secret-url" }
    end
    client.define_singleton_method(:cloud_builds_for_run) do |run|
      raise unless run == "run-id"
      [{ "id" => "build-id", "app_id" => SequelAceRelease::Config::PRODUCTION_APP_ID,
         "version" => "5.3.2", "platform" => "MAC_OS", "build" => 20_105 }]
    end
    client.define_singleton_method(:run_artifacts) do |_run|
      [{ "attributes" => { "downloadUrl" => "https://example.invalid/private-token" } }]
    end
    manifest = Struct.new(:to_h).new({
      "tag" => "production/5.3.2-20105", "target_version" => "5.3.2",
      "canonical_build" => 20_105, "state" => "cloud_running", "channel" => "production",
      "release_commit_sha" => "a" * 40, "cloud_build_ids" => { "production" => "run-id" }
    })
    result = SequelAceRelease::ReleaseStatus.new(client: client, production_workflow_id: "workflow").inspect(
      manifest: manifest, app_store_notes: "notes"
    )
    assert_equal "ready", result.dig("cloud", "readiness")
    refute_includes JSON.generate(result), "secret-url"
    refute_includes JSON.generate(result), "private-token"
  end

  def test_missing_schedule_does_not_validate_metadata
    snapshot = metadata_snapshot(state: "WAITING_FOR_REVIEW")
    snapshot["version"]["attributes"].delete("earliestReleaseDate")
    refute report(snapshot).dig("app_store", "metadata_valid")
  end

  def test_live_release_uses_distribution_checks_instead_of_submission_schedule
    snapshot = metadata_snapshot(state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    snapshot["version"]["attributes"]["releaseType"] = "AFTER_APPROVAL"
    snapshot["version"]["attributes"].delete("earliestReleaseDate")

    result = report(snapshot)
    assert result.dig("app_store", "metadata_valid")
    assert result.dig("app_store", "submitted")
    assert_includes result.fetch("next_action"), "finalizer owns"

    snapshot["phased_release"]["attributes"]["phasedReleaseState"] = "PAUSED"
    result = report(snapshot)
    refute result.dig("app_store", "metadata_valid")
    assert_includes result.dig("app_store", "metadata_error"), "phased release is not active"
  end

  def test_incomplete_localization_reports_metadata_gap
    client = Client.new(metadata_snapshot)
    client.define_singleton_method(:metadata_snapshot) { |**| raise SequelAceRelease::ValidationError, "localization missing" }
    manifest = Struct.new(:to_h).new({ "tag" => "production/5.3.2-20105", "target_version" => "5.3.2", "canonical_build" => 20_105, "state" => "archived", "channel" => "production" })
    result = SequelAceRelease::ReleaseStatus.new(client: client).inspect(manifest: manifest, app_store_notes: "notes")
    assert result.dig("app_store", "exists")
    refute result.dig("app_store", "metadata_valid")
  end
end
