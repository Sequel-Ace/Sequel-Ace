# frozen_string_literal: true

require "test_helper"

class ReleaseFailureRecoveryTest < Minitest::Test
  class AppStoreClient
    def initialize(version:, selected_build: nil)
      @version = version
      @selected_build = selected_build
    end

    def app_store_version(app_id:, version:)
      raise "wrong app" unless app_id == SequelAceRelease::Config::PRODUCTION_APP_ID
      raise "wrong version" unless version == "5.3.2"

      @version
    end

    def selected_build(version_id:)
      raise "wrong version id" unless version_id == "version-id"

      @selected_build
    end
  end

  def test_reconciles_the_exact_submitted_version_and_build
    reconciler = SequelAceRelease::SubmissionReconciler.new(
      client: AppStoreClient.new(
        version: app_store_version("WAITING_FOR_REVIEW"),
        selected_build: selected_build(20_105)
      )
    )

    result = reconciler.reconcile(manifest)
    assert_equal true, result.fetch("submitted")
    assert_equal "version-id", result.fetch("version_id")
    assert_equal "build-id", result.fetch("build_id")
  end

  def test_does_not_treat_a_staged_version_as_submitted
    reconciler = SequelAceRelease::SubmissionReconciler.new(
      client: AppStoreClient.new(version: app_store_version("PREPARE_FOR_SUBMISSION"))
    )

    result = reconciler.reconcile(manifest)
    assert_equal false, result.fetch("submitted")
    assert_equal "state_not_submitted", result.fetch("reason")
  end

  def test_does_not_treat_an_absent_version_as_submitted
    reconciler = SequelAceRelease::SubmissionReconciler.new(client: AppStoreClient.new(version: nil))

    result = reconciler.reconcile(manifest)
    assert_equal false, result.fetch("submitted")
    assert_equal "version_not_found", result.fetch("reason")
  end

  def test_rejects_a_submitted_version_with_the_wrong_build
    reconciler = SequelAceRelease::SubmissionReconciler.new(
      client: AppStoreClient.new(
        version: app_store_version("IN_REVIEW"),
        selected_build: selected_build(20_106)
      )
    )

    error = assert_raises(SequelAceRelease::ValidationError) { reconciler.reconcile(manifest) }
    assert_includes error.message, "does not match"
  end

  def test_unsubmitted_failure_becomes_failed_and_can_explain_the_prerelease
    result = recorder.record(
      manifest: manifest(state: "archived"),
      workflow_url: workflow_url
    )

    assert_equal "failed", result.manifest.to_h.fetch("state")
    assert_equal false, result.preserve_release_body
    assert_equal workflow_url, result.manifest.to_h.dig("failure", "workflow_url")
  end

  def test_submitted_failure_preserves_state_and_the_immutable_release_body
    existing = manifest(state: "submitted").with(
      "asc_ids" => { "version_id" => "version-id", "build_id" => "build-id" }
    )
    result = recorder.record(manifest: existing, workflow_url: workflow_url)

    assert_equal "submitted", result.manifest.to_h.fetch("state")
    assert_equal true, result.preserve_release_body
    assert_equal "version-id", result.manifest.to_h.dig("asc_ids", "version_id")
  end

  def test_reconciled_submission_recovers_an_archived_manifest
    result = recorder.record(
      manifest: manifest(state: "archived"),
      workflow_url: workflow_url,
      submission: {
        "submitted" => true,
        "reason" => "exact_submission_confirmed",
        "version_id" => "version-id",
        "build_id" => "build-id",
        "app_store_state" => "WAITING_FOR_REVIEW"
      }
    )

    assert_equal "submitted", result.manifest.to_h.fetch("state")
    assert_equal true, result.preserve_release_body
    assert_equal true, result.submission_confirmed
    refute result.manifest.to_h.fetch("asc_ids").key?("reason")
  end

  def test_rejects_unconfirmed_submission_evidence
    error = assert_raises(SequelAceRelease::ValidationError) do
      recorder.record(
        manifest: manifest(state: "archived"),
        workflow_url: workflow_url,
        submission: {
          "submitted" => false,
          "version_id" => "version-id",
          "build_id" => "build-id",
          "app_store_state" => "PREPARE_FOR_SUBMISSION"
        }
      )
    end
    assert_includes error.message, "not confirmed"
  end

  def test_prepare_pr_persists_commit_evidence_before_pr_creation
    release_approval = approval
    commit_sha = "d" * 40
    git = Object.new
    git.define_singleton_method(:sha) { release_approval.payload.fetch("main_sha") }
    changed_paths = (
      SequelAceRelease::Config::PROJECT_FILES.keys +
      SequelAceRelease::Config::PLIST_FILES +
      ["CHANGELOG.md"]
    ).map { |path| { "status" => " M", "path" => path } }
    git.define_singleton_method(:changed_paths) { changed_paths }
    github = Object.new
    github.define_singleton_method(:create_bot_commit) do |**_options|
      { "sha" => commit_sha, "verification" => { "verified" => true } }
    end
    github.define_singleton_method(:create_pull_request) do |**_options|
      raise SequelAceRelease::APIError, "simulated PR creation failure"
    end

    Dir.mktmpdir do |directory|
      approval_path = File.join(directory, "approval.json")
      body_path = File.join(directory, "release-body.md")
      output_path = File.join(directory, "release-pr.json")
      File.write(approval_path, SequelAceRelease::CanonicalJSON.pretty(release_approval.to_h))
      File.write(body_path, "## App Store Release Notes\n\nA focused release note.\n")
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

      status = SequelAceRelease::GitRepository.stub(:new, git) do
        cli.stub(:github_client, github) do
          cli.run([
            "github-prepare-pr",
            "--approval", approval_path,
            "--approval-sha", release_approval.sha256,
            "--build", "20105",
            "--release-body", body_path,
            "--output", output_path
          ])
        end
      end

      assert_equal 1, status
      recovery = JSON.parse(File.read(output_path))
      assert_equal commit_sha, recovery.dig("commit", "sha")
      assert_nil recovery["pull_request"]
    end
  end

  private

  def manifest(state: "archived")
    release_approval = approval
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 1
    )
    SequelAceRelease::Manifest.create(
      approval: release_approval,
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_105,
      release_notes_sha256: "c" * 64,
      state: state
    )
  end

  def app_store_version(state)
    {
      "id" => "version-id",
      "attributes" => { "appStoreState" => state }
    }
  end

  def selected_build(build)
    {
      "id" => "build-id",
      "attributes" => { "version" => build.to_s }
    }
  end

  def recorder
    SequelAceRelease::FailureRecorder.new
  end

  def workflow_url
    "https://github.com/Sequel-Ace/Sequel-Ace/actions/runs/123"
  end
end
