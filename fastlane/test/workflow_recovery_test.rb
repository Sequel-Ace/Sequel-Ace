# frozen_string_literal: true

require "test_helper"

class WorkflowRecoveryTest < Minitest::Test
  def test_release_wait_uses_job_token_then_refreshes_app_tokens_for_mutations
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    wait_step = workflow.index("- name: Wait for exact-head release PR checks")
    merge_token_step = workflow.index("- name: Refresh release App token before merging")
    merge_step = workflow.index("- name: Recheck and merge the release PR")
    cleanup_token_step = workflow.index("- name: Refresh release App token for failure cleanup")
    cleanup_step = workflow.index("- name: Reconcile a failed release branch")

    assert wait_step
    assert merge_token_step
    assert merge_step
    assert cleanup_token_step
    assert cleanup_step
    assert_operator wait_step, :<, merge_token_step
    assert_operator merge_token_step, :<, merge_step
    assert_operator cleanup_token_step, :<, cleanup_step
    assert_includes workflow[wait_step...merge_token_step], "SA_GITHUB_TOKEN: ${{ github.token }}"
    assert_includes workflow[merge_step...cleanup_token_step], "SA_GITHUB_TOKEN: ${{ steps.merge_app_token.outputs.token }}"
    assert_includes workflow[cleanup_step..], "steps.cleanup_app_token.outputs.token || github.token"
  end

  def test_cloud_target_is_reconciled_again_after_checks_and_before_merge_or_tag
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    wait_step = workflow.index("- name: Wait for exact-head release PR checks")
    fresh_token = workflow.index("- name: Refresh release App token before merging")
    reconcile_again = workflow.index("- name: Revalidate Production Cloud build immediately before merge or tag")
    merge_step = workflow.index("- name: Recheck and merge the release PR")
    tag_step = workflow.index("- name: Create the tag-backed GitHub prerelease")

    assert_operator wait_step, :<, fresh_token
    assert_operator fresh_token, :<, reconcile_again
    assert_operator reconcile_again, :<, merge_step
    assert_operator merge_step, :<, tag_step
    assert_includes workflow[reconcile_again...merge_step], "--expected-target-build"
    assert_includes workflow[reconcile_again...merge_step], "mv pre-merge-reconciliation.json reconciliation.json"
  end

  def test_cancelled_release_runs_branch_and_prerelease_recovery
    release = File.read(repo_path(".github/workflows/release.yml"))
    cleanup_token = release[/\s+if: .*\n\s+id: cleanup_app_token/, 0]
    cleanup_step = release.split("- name: Reconcile a failed release branch", 2).fetch(1).lines.first(2).join
    prerelease_step = release.split("- name: Preserve an explanatory failed prerelease", 2).fetch(1).lines.first(2).join
    alpha = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    alpha_step = alpha.split("- name: Preserve Alpha retry failure evidence", 2).fetch(1).lines.first(2).join

    assert_includes cleanup_token, "failure() || cancelled()"
    assert_includes cleanup_step, "failure() || cancelled()"
    assert_includes prerelease_step, "failure() || cancelled()"
    assert_includes alpha_step, "failure() || cancelled()"
  end

  def test_transient_workflow_evidence_cannot_pollute_release_commit_paths
    release = File.read(repo_path(".github/workflows/release.yml"))
    release_exclusion = release.index("- name: Exclude transient release evidence from git status")
    release_plan = release.index("- name: Decode and validate the approved plan")
    assert_operator release_exclusion, :<, release_plan
    assert_includes release[release_exclusion...release_plan], "/release-plan.json"
    assert_includes release[release_exclusion...release_plan], "/manifest.json"

    feasibility = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    feasibility_exclusion = feasibility.index("- name: Exclude transient feasibility evidence from git status")
    feasibility_probe = feasibility.index("- name: Create the verified GitHub App commit and disposable PR")
    assert_operator feasibility_exclusion, :<, feasibility_probe
    assert_includes feasibility[feasibility_exclusion...feasibility_probe], "/feasibility/"
  end

  def test_ambiguous_app_store_submission_is_polled_before_failure_recording
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    failure_step = workflow.split("- name: Preserve an explanatory failed prerelease", 2).fetch(1)
    reconcile = failure_step.index("reconcile-submission")
    record = failure_step.index("record-failure")

    refute_nil reconcile
    refute_nil record
    assert_operator reconcile, :<, record
    assert_includes failure_step[reconcile...record], "--wait-seconds 900"
    assert_includes failure_step[reconcile...record], "--poll-interval 15"
  end

  def test_finalizer_archives_live_validation_before_the_public_transition
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    validation = workflow.index("--validate-only")
    archive = workflow.index('Scripts/archive-release-to-ghcr.sh push "${archive_ref}"')
    public_transition = workflow.index('--output "${work_directory}/finalization.json"')

    assert validation
    assert archive
    assert public_transition
    assert_operator validation, :<, archive
    assert_operator archive, :<, public_transition
  end

  def test_feasibility_wait_and_cleanup_do_not_reuse_the_probe_app_token
    workflow = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    create_token = workflow.index("- name: Mint a fresh release App token for the GitHub probe")
    create_probe = workflow.index("- name: Create the verified GitHub App commit and disposable PR")
    wait_checks = workflow.index("- name: Wait for exact-head feasibility PR checks")
    cleanup_token = workflow.index("- name: Refresh release App token for probe cleanup")
    cleanup_probe = workflow.index("- name: Close and delete only the exact feasibility probe")

    assert_operator create_token, :<, create_probe
    assert_operator create_probe, :<, wait_checks
    assert_operator wait_checks, :<, cleanup_token
    assert_operator cleanup_token, :<, cleanup_probe
    assert_includes workflow[wait_checks...cleanup_token], "SA_GITHUB_TOKEN: ${{ github.token }}"
    assert_includes workflow[cleanup_probe..], "steps.probe_cleanup_token.outputs.token || github.token"
  end

  def test_alpha_failure_uses_the_checkpoint_preserving_recorder
    workflow = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    failure_step = workflow.split("- name: Preserve Alpha retry failure evidence", 2).fetch(1)

    assert_includes failure_step, "sa-release record-failure"
    refute_includes failure_step, "--state failed"
  end

  private

  def repo_path(relative_path)
    File.expand_path("../..", __dir__) + "/#{relative_path}"
  end
end
