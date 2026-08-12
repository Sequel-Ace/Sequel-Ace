# frozen_string_literal: true

require "test_helper"

class DeploymentGuardTest < Minitest::Test
  def setup
    @guard = SequelAceRelease::DeploymentGuard.new
    @valid = {
      actor: "Jason-Morcos",
      triggering_actor: "Jason-Morcos",
      mode: "start",
      ref: "refs/heads/main",
      current_sha: "a" * 40,
      expected_sha: "a" * 40,
      channel: "production",
      version: "5.3.2",
      confirmation: "RELEASE production 5.3.2",
      enabled: "true"
    }
  end

  def test_accepts_only_the_locked_release_gate
    result = @guard.validate!(**@valid)
    assert_equal "Jason-Morcos", result.fetch("actor")
    assert_equal "Jason-Morcos", result.fetch("triggering_actor")
    assert_equal false, result.fetch("automated_recovery")
  end

  def test_rejects_actor_ref_main_movement_and_confirmation_changes
    %i[actor triggering_actor mode ref expected_sha confirmation enabled].each do |field|
      invalid = @valid.merge(field => {
        actor: "someone-else",
        triggering_actor: "someone-else",
        mode: "invalid",
        ref: "refs/heads/release",
        expected_sha: "b" * 40,
        confirmation: "RELEASE production 5.3.2 ",
        enabled: "false"
      }.fetch(field))
      assert_raises(SequelAceRelease::ValidationError, field.to_s) do
        @guard.validate!(**invalid)
      end
    end
  end

  def test_kaspik_and_beta_are_authorized_with_their_exact_confirmation
    result = @guard.validate!(**@valid.merge(
      actor: "Kaspik",
      triggering_actor: "Kaspik",
      channel: "beta",
      confirmation: "RELEASE beta 5.3.2"
    ))
    assert_equal "beta", result.fetch("channel")
  end

  def test_an_authorized_user_can_rerun_another_authorized_users_dispatch
    result = @guard.validate!(**@valid.merge(triggering_actor: "Kaspik"))

    assert_equal "Jason-Morcos", result.fetch("actor")
    assert_equal "Kaspik", result.fetch("triggering_actor")
  end

  def test_resume_provisionally_allows_an_older_approved_sha_for_later_ancestry_validation
    result = @guard.validate!(**@valid.merge(
      mode: "resume",
      current_sha: "b" * 40
    ))

    assert_equal true, result.fetch("requires_release_ancestor_validation")
    assert_equal "a" * 40, result.fetch("approved_main_sha")
    assert_equal "b" * 40, result.fetch("dispatch_main_sha")
  end

  def test_start_still_rejects_an_advanced_main
    assert_raises(SequelAceRelease::ValidationError) do
      @guard.validate!(**@valid.merge(current_sha: "b" * 40))
    end
  end

  def test_sha_validation_accepts_only_git_object_id_lengths
    assert @guard.validate!(**@valid.merge(
      current_sha: "A" * 64,
      expected_sha: "a" * 64
    ))
    assert_raises(SequelAceRelease::ValidationError) do
      @guard.validate!(**@valid.merge(current_sha: "a" * 41, expected_sha: "a" * 41))
    end
  end

  def test_actions_bot_is_allowed_only_for_an_exact_automatic_recovery
    result = @guard.validate!(**@valid.merge(
      actor: "github-actions[bot]",
      triggering_actor: "github-actions[bot]",
      mode: "resume",
      recovery_tag: "production/5.3.2-20105"
    ))

    assert_equal true, result.fetch("automated_recovery")
    assert_equal "production/5.3.2-20105", result.fetch("recovery_tag")
    assert_raises(SequelAceRelease::ValidationError) do
      @guard.validate!(**@valid.merge(
        actor: "github-actions[bot]",
        triggering_actor: "github-actions[bot]",
        mode: "resume"
      ))
    end
  end

  def test_human_dispatch_cannot_forge_automatic_recovery
    assert_raises(SequelAceRelease::ValidationError) do
      @guard.validate!(**@valid.merge(
        mode: "resume",
        recovery_tag: "production/5.3.2-20105"
      ))
    end
  end
end
