# frozen_string_literal: true

require "test_helper"

class BuildReconcilerTest < Minitest::Test
  WORKFLOW_ID = "DB2243BC-F641-472D-995E-3C9198C235DE"

  def setup
    @reconciler = SequelAceRelease::BuildReconciler.new
  end

  def test_expected_next_is_highest_observed_build_plus_one
    result = reconcile(cloud_runs: [cloud_run(20_104)])

    assert_equal 20_105, result.target_build
    assert_equal "normal_increment", result.reason
    assert_equal 20_104, result.production_build_evidence.fetch("highest_observed_build")
    assert_equal 20_105, result.production_build_evidence.fetch("expected_next_build")
    assert_empty result.skipped_runs
  end

  def test_highest_app_store_build_also_advances_the_floor
    result = reconcile(highest_asc_build: 20_106, cloud_runs: [cloud_run(20_104)])

    assert_equal 20_107, result.target_build
    assert_equal "self_healed_forward_jump", result.reason
    assert_equal [20_105, 20_106], result.skipped_runs.map { |entry| entry.fetch("number") }
    assert result.skipped_runs.all? { |entry| entry.fetch("reason") == "app_store_connect_counter_floor" }
  end

  def test_a_higher_cloud_assignment_proves_a_forward_counter_jump
    result = reconcile(
      source_build: 20_105,
      highest_tag_build: 20_105,
      cloud_runs: [cloud_run(20_112, status: "FAILED")]
    )

    assert_equal 20_113, result.target_build
    assert_equal "self_healed_forward_jump", result.reason
    jump = result.skipped_runs.find { |entry| entry.fetch("number") == 20_106 }
    assert_equal "production_cloud_counter_jump", jump.fetch("reason")
    assert_equal 20_112, jump.fetch("evidenced_by_build")
    consumed = result.skipped_runs.find { |entry| entry.fetch("number") == 20_112 }
    assert_equal "production_cloud_run", consumed.fetch("reason")
    assert_equal "run-20112", consumed.fetch("id")
  end

  def test_resume_after_merged_release_pr_reuses_the_unconsumed_candidate
    result = reconcile(
      source_build: 20_105,
      source_tagged: false,
      source_release_commit_sha: "d" * 40,
      cloud_runs: [cloud_run(20_104)]
    )

    assert_equal "resume_after_merge", result.reason
    assert_equal 20_105, result.target_build
    assert_equal "d" * 40, result.source_release_commit_sha
  end

  def test_resume_after_merge_moves_forward_after_cloud_consumes_the_candidate
    result = reconcile(
      source_build: 20_105,
      source_tagged: false,
      source_release_commit_sha: "d" * 40,
      cloud_runs: [cloud_run(20_105, status: "FAILED")]
    )

    assert_equal "normal_increment", result.reason
    assert_equal 20_106, result.target_build
  end

  def test_unexplained_source_advance_aborts
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_107,
        source_tagged: false,
        source_release_commit_sha: "d" * 40,
        cloud_runs: [cloud_run(20_104)]
      )
    end

    assert_includes error.message, "ahead of API-derived"
  end

  def test_preincremented_unreleased_source_uses_the_derived_build_without_recovery
    result = reconcile(
      source_build: 20_105,
      source_tagged: false,
      cloud_runs: [cloud_run(20_104)]
    )

    assert_equal "normal_increment", result.reason
    assert_equal 20_105, result.target_build
    assert_nil result.source_release_commit_sha
    assert_empty result.skipped_runs
  end

  def test_release_tag_cannot_be_ahead_of_source
    assert_raises(SequelAceRelease::ValidationError) do
      reconcile(source_build: 20_104, highest_tag_build: 20_105, cloud_runs: [cloud_run(20_104)])
    end
  end

  def test_failed_rc_continues_at_highest_plus_one
    result = reconcile(
      source_build: 20_105,
      highest_tag_build: 20_105,
      highest_asc_build: 20_105,
      cloud_runs: [cloud_run(20_105, status: "FAILED")],
      source_tagged: true
    )

    assert_equal 20_106, result.target_build
    assert_equal "normal_increment", result.reason
  end

  def test_tag_only_recovery_reuses_the_source_before_cloud_consumes_it
    result = reconcile(
      source_build: 20_105,
      highest_tag_build: 20_105,
      highest_asc_build: 20_104,
      cloud_runs: [cloud_run(20_104)],
      source_tagged: true,
      source_release_commit_sha: "a" * 40,
      recover_release_tag: "production/5.4.0-20105",
      production_workflow_id: WORKFLOW_ID
    )

    assert_equal 20_105, result.target_build
    assert_equal "resume_after_tag", result.reason
  end

  def test_tag_only_recovery_reuses_the_exact_consumed_cloud_run
    result = reconcile(
      source_build: 20_105,
      highest_tag_build: 20_105,
      highest_asc_build: 20_105,
      source_tagged: true,
      source_release_commit_sha: "a" * 40,
      recover_release_tag: "production/5.4.0-20105",
      production_workflow_id: WORKFLOW_ID,
      cloud_runs: [cloud_run(20_105).merge(
        "execution_progress" => "COMPLETE",
        "source_commit" => "a" * 40,
        "git_reference" => "production/5.4.0-20105",
        "workflow_id" => WORKFLOW_ID
      )]
    )

    assert_equal 20_105, result.target_build
    assert_equal "resume_after_tag", result.reason
  end

  def test_tag_only_recovery_rejects_a_later_cloud_run
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_105,
        highest_tag_build: 20_105,
        source_tagged: true,
        source_release_commit_sha: "a" * 40,
        recover_release_tag: "production/5.4.0-20105",
        production_workflow_id: WORKFLOW_ID,
        cloud_runs: [cloud_run(20_106)]
      )
    end

    assert_includes error.message, "advanced beyond"
  end

  def test_pre_merge_reconciliation_aborts_if_api_evidence_advances_the_target
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        expected_target_build: 20_105,
        cloud_runs: [cloud_run(20_105, status: "FAILED")]
      )
    end

    assert_includes error.message, "changed from expected 20105 to 20106"
    assert_includes error.message, "abort before merging or tagging"
  end

  def test_pre_merge_reconciliation_accepts_the_unchanged_target
    result = reconcile(expected_target_build: 20_105, cloud_runs: [cloud_run(20_104)])

    assert_equal 20_105, result.target_build
  end

  def test_duplicate_or_malformed_cloud_evidence_aborts
    assert_raises(SequelAceRelease::ValidationError) do
      reconcile(cloud_runs: [cloud_run(20_104), cloud_run(20_104)])
    end
    assert_raises(SequelAceRelease::ValidationError) do
      reconcile(cloud_runs: [{ "id" => "", "number" => 20_104 }])
    end
  end

  def test_alpha_numbers_are_not_an_input
    method_parameters = @reconciler.method(:reconcile).parameters.map(&:last)
    refute_includes method_parameters, :alpha_build
    refute_includes method_parameters, :alpha_runs
  end

  private

  def reconcile(overrides = {})
    @reconciler.reconcile(**{
      source_build: 20_104,
      highest_tag_build: 20_104,
      highest_asc_build: 20_104,
      cloud_runs: [],
      source_tagged: true
    }.merge(overrides))
  end

  def cloud_run(number, status: "SUCCEEDED")
    {
      "id" => "run-#{number}",
      "number" => number,
      "execution_progress" => "COMPLETE",
      "completion_status" => status,
      "source_commit" => number.to_s.rjust(40, "0")
    }
  end
end
