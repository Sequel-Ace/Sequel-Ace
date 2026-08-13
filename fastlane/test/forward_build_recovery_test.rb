# frozen_string_literal: true

require "test_helper"

class ForwardBuildRecoveryTest < Minitest::Test
  BODY = <<~BODY.freeze
    ## App Store Release Notes

    A focused release note.

    ## What's Changed

    - A tested fix.
  BODY

  class GitHub
    attr_reader :validated_target

    def initialize(assets: [])
      @assets = assets
    end

    def ref_sha(_ref)
      "d" * 40
    end

    def validate_release_target!(target_sha:, protected_paths:)
      @validated_target = { target_sha: target_sha, protected_paths: protected_paths }
    end

    def release_by_tag(tag)
      {
        "tag_name" => tag,
        "draft" => false,
        "prerelease" => true,
        "name" => "5.3.2 (20109) - Release Candidate 1",
        "author" => { "login" => SequelAceRelease::ReleasePublisher::USER_LOGIN },
        "created_at" => "2026-08-13T00:00:00Z",
        "assets" => @assets
      }
    end
  end

  def test_validates_a_higher_assignment_and_authorizes_assigned_plus_one
    github = GitHub.new
    result = validator(github).validate(**arguments)

    assert_equal 20_109, result.fetch("failed_expected_build")
    assert_equal 20_112, result.fetch("cloud_assigned_build")
    assert_equal 20_113, result.fetch("expected_recovery_build")
    assert_equal 1, result.fetch("count")
    assert_equal "d" * 40, github.validated_target.fetch(:target_sha)
  end

  def test_rejects_a_non_forward_mismatch
    changed = manifest.with(
      "failure" => manifest.to_h.fetch("failure").merge(
        "reason" => "cloud_build_number_regressed",
        "assigned_build" => 20_104,
        "recovery_build" => nil
      )
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(manifest: changed))
    end
    assert_includes error.message, "number-advance"
  end

  def test_rejects_a_recovery_build_that_is_not_assigned_plus_one
    changed = manifest.with(
      "failure" => manifest.to_h.fetch("failure").merge("recovery_build" => 20_120)
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(manifest: changed))
    end
    assert_includes error.message, "inconsistent"
  end

  def test_rejects_an_approval_hash_that_does_not_match
    assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(approval_sha: "f" * 64))
    end
  end

  def test_rejects_a_missing_failure_record_with_the_specific_recovery_error
    changed = manifest.to_h.reject { |key, _value| key == "failure" }

    error = assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(manifest: SequelAceRelease::Manifest.new(changed)))
    end
    assert_includes error.message, "number-advance failure"
  end

  def test_reports_only_an_invalid_recovery_count_as_a_count_error
    changed = manifest.with("forward_build_recovery" => { "count" => "invalid" })

    error = assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(manifest: changed))
    end
    assert_includes error.message, "count must be an integer"
  end

  def test_rejects_recovery_after_main_or_release_assets_change
    assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(current_sha: "e" * 40))
    end
    error = assert_raises(SequelAceRelease::ValidationError) do
      validator(GitHub.new(assets: [{ "name" => "unexpected.zip" }])).validate(**arguments)
    end
    assert_includes error.message, "after release assets"
  end

  def test_rejects_a_noncanonical_archived_release_identity
    changed = manifest.with("title" => "5.3.2 (20109) - Release Candidate 9")

    error = assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(manifest: changed))
    end
    assert_includes error.message, "not canonical"
  end

  def test_caps_automatic_recovery_attempts
    capped = manifest.with(
      "forward_build_recovery" => { "count" => SequelAceRelease::ForwardBuildRecovery::MAX_AUTOMATIC_RECOVERIES }
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      validator.validate(**arguments.merge(manifest: capped))
    end
    assert_includes error.message, "limit"
  end

  private

  def validator(github = GitHub.new)
    SequelAceRelease::ForwardBuildRecovery.new(github: github)
  end

  def arguments
    {
      manifest: manifest,
      approval: release_approval,
      approval_sha: release_approval.sha256,
      release_body: BODY,
      tag: "production/5.3.2-20109",
      current_sha: "d" * 40,
      channel: "production",
      version: "5.3.2",
      previous_tag: "production/5.3.1-20104"
    }
  end

  def release_approval
    @release_approval ||= approval(release_notes_sha256: Digest::SHA256.hexdigest(BODY))
  end

  def manifest
    @manifest ||= begin
      naming = SequelAceRelease::ReleaseNaming.new(
        channel: "production", version: "5.3.2", build: 20_109, iteration: 1
      )
      SequelAceRelease::Manifest.create(
        approval: release_approval,
        naming: naming,
        base_sha: "b" * 40,
        canonical_build: 20_109,
        production_build_evidence: production_build_evidence(target: 20_109),
        release_notes_sha256: Digest::SHA256.hexdigest(BODY),
        state: "failed"
      ).with(
        "release_commit_sha" => "d" * 40,
        "failure" => {
          "reason" => "cloud_build_number_advanced",
          "component" => "production",
          "cloud_run_id" => "run-20112",
          "expected_build" => 20_109,
          "assigned_build" => 20_112,
          "recovery_build" => 20_113
        }
      )
    end
  end
end
