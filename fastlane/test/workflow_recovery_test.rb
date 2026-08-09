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
