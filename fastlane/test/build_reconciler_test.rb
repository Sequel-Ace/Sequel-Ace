# frozen_string_literal: true

require "test_helper"

class BuildReconcilerTest < Minitest::Test
  def setup
    @reconciler = SequelAceRelease::BuildReconciler.new
  end

  def test_normal_increment
    result = reconcile(cloud_next_build: 20_105)

    assert_equal 20_105, result.target_build
    assert_equal "normal_increment", result.reason
    assert_empty result.skipped_runs
  end

  def test_self_heals_only_fully_explained_cloud_burns
    result = reconcile(
      cloud_next_build: 20_108,
      cloud_runs: [
        { "id" => "run-5", "number" => 20_105, "completion_status" => "FAILED", "source_commit" => "a" * 40 },
        { "id" => "run-6", "number" => 20_106, "completion_status" => "SUCCEEDED", "source_commit" => "b" * 40 },
        { "id" => "run-7", "number" => 20_107, "completion_status" => "CANCELED", "source_commit" => "c" * 40 }
      ]
    )

    assert_equal "self_healed_cloud_burns", result.reason
    assert_equal [20_105, 20_106, 20_107], result.skipped_runs.map { |run| run.fetch("number") }
  end

  def test_self_heals_when_the_approved_next_number_burns_before_execution
    result = reconcile(
      cloud_next_build: 20_105,
      cloud_runs: [{
        "id" => "run-5",
        "number" => 20_105,
        "completion_status" => "FAILED",
        "source_commit" => "a" * 40
      }]
    )

    assert_equal 20_105, result.observed_cloud_next_build
    assert_equal 20_106, result.target_build
    assert_equal "self_healed_cloud_burns", result.reason
    assert_equal [20_105], result.skipped_runs.map { |run| run.fetch("number") }
  end

  def test_unexplained_gap_aborts
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        cloud_next_build: 20_107,
        cloud_runs: [{ "id" => "run-5", "number" => 20_105 }]
      )
    end
    assert_includes error.message, "20106"
  end

  def test_resume_after_merged_release_pr_does_not_bump_again
    result = reconcile(source_build: 20_105, cloud_next_build: 20_105, source_tagged: false)

    assert_equal "resume_after_merge", result.reason
    assert_equal 20_105, result.target_build
  end

  def test_resume_after_merge_aborts_if_cloud_already_consumed_the_source_build
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_105,
        cloud_next_build: 20_105,
        source_tagged: false,
        cloud_runs: [{ "id" => "run-5", "number" => 20_105 }]
      )
    end
    assert_includes error.message, "already consumed or advanced"
  end

  def test_resume_after_merge_aborts_if_cloud_advanced_beyond_the_source_build
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_105,
        cloud_next_build: 20_105,
        source_tagged: false,
        cloud_runs: [{ "id" => "run-6", "number" => 20_106 }]
      )
    end
    assert_includes error.message, "20106"
  end

  def test_resume_after_merge_aborts_if_app_store_connect_already_has_the_build
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_105,
        highest_asc_build: 20_105,
        cloud_next_build: 20_105,
        source_tagged: false
      )
    end
    assert_includes error.message, "must be greater than reconciled baseline"
  end

  def test_resume_after_merge_aborts_if_other_changes_landed_after_the_release_merge
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_105,
        cloud_next_build: 20_105,
        source_tagged: false,
        source_is_release_tip: false
      )
    end
    assert_includes error.message, "main HEAD"
  end

  def test_incomplete_burn_evidence_aborts
    error = assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        cloud_next_build: 20_106,
        cloud_runs: [{ "id" => "run-5", "number" => 20_105, "completion_status" => "FAILED" }]
      )
    end
    assert_includes error.message, "source_commit"
  end

  def test_release_tag_cannot_be_ahead_of_source
    assert_raises(SequelAceRelease::ValidationError) do
      reconcile(source_build: 20_104, highest_tag_build: 20_105, cloud_next_build: 20_106)
    end
  end

  def test_failed_rc_continues_at_the_next_cloud_number
    result = reconcile(
      source_build: 20_105,
      highest_tag_build: 20_105,
      highest_asc_build: 20_105,
      cloud_next_build: 20_106,
      source_tagged: true
    )

    assert_equal 20_106, result.target_build
    assert_equal "normal_increment", result.reason
  end

  def test_regression_aborts
    assert_raises(SequelAceRelease::ValidationError) do
      reconcile(source_build: 20_105, cloud_next_build: 20_104)
    end
  end

  def test_regression_is_not_hidden_by_a_later_run
    assert_raises(SequelAceRelease::ValidationError) do
      reconcile(
        source_build: 20_105,
        highest_tag_build: 20_105,
        highest_asc_build: 20_105,
        cloud_next_build: 20_104,
        cloud_runs: [{
          "id" => "run-5",
          "number" => 20_105,
          "completion_status" => "FAILED",
          "source_commit" => "a" * 40
        }]
      )
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
      cloud_next_build: 20_105,
      cloud_runs: [],
      source_tagged: true
    }.merge(overrides))
  end
end
