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
      cloud_next_build: 20_105,
      confirmation: "RELEASE production 5.3.2",
      enabled: "true"
    }
  end

  def test_accepts_only_the_locked_release_gate
    result = @guard.validate!(**@valid)
    assert_equal "Jason-Morcos", result.fetch("actor")
    assert_equal "Jason-Morcos", result.fetch("triggering_actor")
    assert_equal 20_105, result.fetch("cloud_next_build")
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
end
