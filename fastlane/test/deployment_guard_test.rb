# frozen_string_literal: true

require "test_helper"

class DeploymentGuardTest < Minitest::Test
  def setup
    @guard = SequelAceRelease::DeploymentGuard.new
    @valid = {
      actor: "Jason-Morcos",
      triggering_actor: "Jason-Morcos",
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
    %i[actor triggering_actor ref expected_sha confirmation enabled].each do |field|
      invalid = @valid.merge(field => {
        actor: "someone-else",
        triggering_actor: "someone-else",
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
end
