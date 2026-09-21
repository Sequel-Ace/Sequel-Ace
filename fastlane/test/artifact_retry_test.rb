# frozen_string_literal: true
require "test_helper"
require "yaml"
require "open3"

class ArtifactRetryTest < Minitest::Test
  include ReleaseTestHelpers
  class GitHub
    attr_accessor :assets, :moved
    def initialize = @assets = []
    def ref_sha(_ref) = moved ? "f" * 40 : "d" * 40
    def validate_release_target!(**args) = { "current_main_sha" => args.fetch(:target_sha) }
    def file_content(ref:, path:)
      counts = SequelAceRelease::Config::PROJECT_FILES.fetch(path)
      (Array.new(counts.fetch(:current), "CURRENT_PROJECT_VERSION = 20105;") +
        Array.new(counts.fetch(:dylib), "DYLIB_CURRENT_VERSION = 20105;")).join("\n")
    end
    def release_by_tag(tag)
      { "id" => 100, "tag_name" => tag, "draft" => false, "prerelease" => true,
        "name" => "5.3.2 (20105) - Release Candidate 1", "assets" => assets,
        "author" => { "login" => "Jason-Morcos", "id" => 10710367 } }
    end
  end
  class Apple
    attr_accessor :version
    def app_store_version(**_args) = version
  end
  class Cloud
    attr_accessor :result
    attr_reader :arguments
    def initialize
      @result = { "id" => "existing-run", "readiness" => "ready",
                  "execution_progress" => "COMPLETE", "completion_status" => "SUCCEEDED" }
    end
    def readiness(**args)
      @arguments = args
      result
    end
  end
  def setup
    naming = SequelAceRelease::ReleaseNaming.new(channel: "production", version: "5.3.2", build: 20105, iteration: 1)
    @manifest = SequelAceRelease::Manifest.create(
      approval: approval, naming: naming, base_sha: "b" * 40,
      canonical_build: 20105, production_build_evidence: production_build_evidence,
      release_notes_sha256: "c" * 64, state: "failed"
    ).with("release_commit_sha" => "d" * 40, "failure" => { "workflow_url" => "https://github.com/Sequel-Ace/Sequel-Ace/actions/runs/123" })
    @github, @apple, @cloud = GitHub.new, Apple.new, Cloud.new
    @retry = SequelAceRelease::ArtifactRetry.new(github: @github, client: @apple, cloud: @cloud)
  end
  def recover(manifest = @manifest, **overrides)
    bytes = JSON.generate(manifest.to_h)
    @retry.prepare(**{
      manifest_bytes: bytes, expected_digest: Digest::SHA256.hexdigest(bytes),
      tag: manifest.to_h.fetch("tag"), commit: "d" * 40, run_id: "existing-run",
      workflow_id: "production-workflow", notes: "A focused release note.",
      actor: "Jason-Morcos", workflow_url: "https://github.com/Sequel-Ace/Sequel-Ace/actions/runs/456"
    }.merge(overrides))
  end
  def test_reuses_exact_build_and_run_and_preserves_failure
    result = recover.to_h
    assert_equal "cloud_running", result.fetch("state")
    %w[tag title canonical_build release_commit_sha artifact_names].each do |key|
      assert_equal @manifest.to_h.fetch(key), result.fetch(key)
    end
    assert_equal @manifest.to_h.fetch("failure"), result.fetch("artifact_retry_history").last.fetch("previous_failure")
    assert_equal "existing-run", result.dig("cloud_build_ids", "production")
    assert_equal 20105, @cloud.arguments.fetch(:build)
    assert_equal "d" * 40, @cloud.arguments.fetch(:commit)
    assert_equal "existing-run", @cloud.arguments.fetch(:run_id)
    later_failure = SequelAceRelease::Manifest.new(result).with("state" => "failed")
    later_result = recover(later_failure).to_h
    assert_equal 2, later_result.fetch("artifact_retry_history").size
    assert_equal result.fetch("artifact_retry_history").first, later_result.fetch("artifact_retry_history").first
  end
  def test_rejects_changed_fingerprint_identity_and_actor
    [{ expected_digest: "0" * 64 }, { commit: "e" * 40 }, { tag: "production/5.3.2-20106" },
     { actor: "intruder" }, { run_id: "" }].each do |override|
      assert_raises(SequelAceRelease::ValidationError) { recover(**override) }
    end
    @github.moved = true
    assert_raises(SequelAceRelease::ValidationError) { recover }
  end
  def test_rejects_later_publication_state_and_different_archived_run
    [{ "state" => "artifacts_verified" }, { "verification" => { "production" => {} } },
     { "asc_ids" => { "version" => "123" } }, { "failure" => {} },
     { "cloud_build_ids" => { "production" => "other-run" } }].each do |changes|
      assert_raises(SequelAceRelease::ValidationError) { recover(@manifest.with(changes)) }
    end
    @apple.version = { "id" => "existing-version" }
    assert_raises(SequelAceRelease::ValidationError) { recover }
    @apple.version = nil
    @github.assets = [{ "name" => "Sequel-Ace-5.3.2.zip" }]
    assert_raises(SequelAceRelease::ValidationError) { recover }
  end
  def test_rejects_pending_failed_or_different_cloud_run
    [{ "readiness" => "pending" }, { "readiness" => "failed" },
     { "completion_status" => "FAILED" }, { "execution_progress" => "RUNNING" },
     { "id" => "another-run" }].each do |changes|
      previous = @cloud.result
      @cloud.result = previous.merge(changes)
      assert_raises(SequelAceRelease::ValidationError) { recover }
      @cloud.result = previous
    end
  end

  def test_workflow_authentication_and_embedded_ruby
    path = File.expand_path("../../.github/workflows/release_artifact_retry.yml", __dir__)
    workflow = YAML.load_file(path)
    job = workflow.fetch("jobs").fetch("retry")
    assert_equal "sequel-ace-release", job.fetch("environment")
    assert_includes job.fetch("if"), "github.triggering_actor"
    assert_equal "sequel-ace-release", workflow.dig("concurrency", "group")
    steps = job.fetch("steps")
    gate = steps.first.fetch("run")
    base = { "ENABLED" => "true", "RELEASE_REF" => "refs/heads/main", "RELEASE_TAG" => "production/5.3.2-20105",
             "CONFIRMATION" => "RETRY ARTIFACTS production/5.3.2-20105", "PENDING_ARTIFACT" => "none", "PENDING_FINALIZATION" => "none" }
    assert Open3.capture3(base, "bash", "-c", gate).last.success?
    [{ "ENABLED" => "false" }, { "RELEASE_REF" => "refs/heads/feature" }, { "CONFIRMATION" => "wrong" },
     { "PENDING_ARTIFACT" => "production/5.3.2-20106" }, { "PENDING_FINALIZATION" => "production/5.3.1-20104" }].each do |change|
      refute Open3.capture3(base.merge(change), "bash", "-c", gate).last.success?
    end
    script = steps.find { |step| step["name"] == "Validate successful existing run and preserve the failed checkpoint" }.fetch("run")
    ruby = script.split("<<'RUBY'\n", 2).last.split("\nRUBY", 2).first
    assert Open3.capture3(RbConfig.ruby, "-c", stdin_data: ruby).last.success?
  end
end
