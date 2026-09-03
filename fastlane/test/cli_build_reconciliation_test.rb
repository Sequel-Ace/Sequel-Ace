# frozen_string_literal: true

require "test_helper"

class CliBuildReconciliationTest < Minitest::Test
  def test_forward_recovery_pr_evidence_is_bound_to_the_approved_release_identity
    release_approval = approval
    approval_sha = release_approval.sha256
    expected_sha = "d" * 40
    evidence = {
      "predecessor_tag" => "production/5.3.2-20105",
      "predecessor_release_commit_sha" => expected_sha,
      "failed_expected_build" => 20_105,
      "expected_recovery_build" => 20_113,
      "approval_sha256" => approval_sha
    }
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

    cli.send(
      :validate_forward_recovery_pr_evidence!,
      evidence,
      approval: release_approval,
      approval_sha: approval_sha,
      expected_sha: expected_sha,
      requested_build: 20_113
    )

    [
      evidence.merge("predecessor_tag" => "beta/5.3.2-20105"),
      evidence.merge("predecessor_tag" => "production/5.4.0-20105"),
      evidence.merge("predecessor_tag" => "production/5.3.2-20106")
    ].each do |mismatch|
      assert_raises(SequelAceRelease::ValidationError, mismatch.fetch("predecessor_tag")) do
        cli.send(
          :validate_forward_recovery_pr_evidence!,
          mismatch,
          approval: release_approval,
          approval_sha: approval_sha,
          expected_sha: expected_sha,
          requested_build: 20_113
        )
      end
    end

    assert_raises(SequelAceRelease::ValidationError) do
      cli.send(
        :validate_forward_recovery_pr_evidence!,
        evidence.merge("expected_recovery_build" => 20_112),
        approval: release_approval,
        approval_sha: approval_sha,
        expected_sha: expected_sha,
        requested_build: 20_113
      )
    end
  end

  def test_canonical_tag_baseline_includes_production_and_beta_tags
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    tags = [
      "production/5.3.1-20104",
      "beta/5.3.2-20106",
      "unrelated/5.3.2-99999"
    ]

    assert_equal 20_106, cli.send(:highest_build_from_tags, tags)
  end

  def test_reconcile_build_refuses_a_number_already_claimed_by_a_beta_tag
    git = Object.new
    git.define_singleton_method(:tags) do |pattern|
      pattern == "beta/*" ? ["beta/5.3.2-20106"] : []
    end
    git.define_singleton_method(:latest_commit_changing_all) { |_paths| nil }
    output = StringIO.new
    error = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: error, env: {})

    status = SequelAceRelease::GitRepository.stub(:new, git) do
      cli.run([
        "reconcile-build",
        "--source-build", "20105",
        "--highest-asc-build", "20104"
      ])
    end

    assert_equal 1, status
    assert_includes error.string, "canonical release tag build 20106 is ahead of source build 20105"
  end

  def test_reconcile_build_reuses_an_exact_declared_source_identity
    identity = {
      "channel" => "beta",
      "version" => "6.0.0",
      "build" => 20_111,
      "tag" => "beta/6.0.0-20111"
    }
    git = Object.new
    git.define_singleton_method(:tags) { |_pattern| [] }
    git.define_singleton_method(:latest_commit_changing_all) { |_paths| nil }
    files = Object.new
    files.define_singleton_method(:release_identity) { identity }
    output = StringIO.new
    error = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: error, env: {})

    status = SequelAceRelease::VersionFiles.stub(:new, files) do
      SequelAceRelease::GitRepository.stub(:new, git) do
        cli.run([
          "reconcile-build",
          "--source-build", "20111",
          "--channel", "beta",
          "--target-version", "6.0.0",
          "--highest-asc-build", "20110"
        ])
      end
    end

    assert_equal 0, status
    result = JSON.parse(output.string)
    assert_equal "preincremented_source", result.fetch("reason")
    assert_equal identity, result.dig("production_build_evidence", "source_release_identity")
    assert_empty error.string
  end

  def test_reconcile_build_rejects_a_source_build_that_disagrees_with_its_identity
    identity = {
      "channel" => "beta",
      "version" => "6.0.0",
      "build" => 20_111,
      "tag" => "beta/6.0.0-20111"
    }
    files = Object.new
    files.define_singleton_method(:release_identity) { identity }
    output = StringIO.new
    error = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: error, env: {})

    status = SequelAceRelease::VersionFiles.stub(:new, files) do
      cli.run([
        "reconcile-build",
        "--source-build", "20112",
        "--channel", "beta",
        "--target-version", "6.0.0",
        "--highest-asc-build", "20110"
      ])
    end

    assert_equal 1, status
    assert_includes error.string, "does not match the prepared source build"
    assert_empty output.string
  end

  def test_tag_only_recovery_validates_the_missing_release_and_enriches_its_cloud_run
    commit = "a" * 40
    tag = "production/5.4.0-20105"
    git = Object.new
    git.define_singleton_method(:tag_exists?) { |candidate| candidate == tag }
    git.define_singleton_method(:sha) { |_ref| commit }
    github = Object.new
    github.define_singleton_method(:release_by_tag) do |_candidate|
      raise SequelAceRelease::APIError.new(
        "GitHub API returned HTTP 404: Not Found",
        status: 404
      )
    end
    apple = Object.new
    apple.define_singleton_method(:build_run) do |run_id|
      raise "wrong run" unless run_id == "run-20105"

      {
        "workflow_id" => "DB2243BC-F641-472D-995E-3C9198C235DE",
        "git_reference" => tag,
        "source_commit" => commit
      }
    end
    runs = [{ "id" => "run-20105", "number" => 20_105 }]
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

    recovered = cli.stub(:github_client, github) do
      cli.send(
        :recover_release_tag,
        options: {
          recover_release_channel: "production",
          recover_release_version: "5.4.0",
          workflow_id: "DB2243BC-F641-472D-995E-3C9198C235DE"
        },
        git: git,
        source_build: 20_105,
        source_release_commit_sha: commit,
        runs: runs,
        app_store_client: apple
      )
    end

    assert_equal tag, recovered
    assert_equal tag, runs.first.fetch("git_reference")
    assert_equal commit, runs.first.fetch("source_commit")
  end

  def test_tag_only_recovery_is_not_selected_when_the_prerelease_exists
    commit = "a" * 40
    git = Object.new
    git.define_singleton_method(:tag_exists?) { |_candidate| true }
    git.define_singleton_method(:sha) { |_ref| commit }
    github = Object.new
    github.define_singleton_method(:release_by_tag) { |_candidate| { "id" => 100 } }
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

    recovered = cli.stub(:github_client, github) do
      cli.send(
        :recover_release_tag,
        options: {
          recover_release_channel: "production",
          recover_release_version: "5.4.0",
          workflow_id: "DB2243BC-F641-472D-995E-3C9198C235DE"
        },
        git: git,
        source_build: 20_105,
        source_release_commit_sha: commit,
        runs: [],
        app_store_client: Object.new
      )
    end

    assert_nil recovered
  end
end
