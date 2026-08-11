# frozen_string_literal: true

require "test_helper"

class PublishHandoffTest < Minitest::Test
  BODY = <<~BODY.freeze
    ## App Store Release Notes

    A focused release note.

    ## What's Changed

    - A tested change.
  BODY
  APP_STORE_NOTES = "A focused release note.".freeze

  class GitHub
    attr_reader :target_arguments

    def initialize(release:, ref_sha: "d" * 40, target_error: nil)
      @release = release
      @ref_sha = ref_sha
      @target_error = target_error
    end

    def ref_sha(_ref)
      @ref_sha
    end

    def release_by_tag(_tag)
      @release
    end

    def validate_release_target!(**arguments)
      @target_arguments = arguments
      raise @target_error if @target_error

      { "target_sha" => arguments.fetch(:target_sha), "current_main_sha" => arguments.fetch(:target_sha) }
    end
  end

  def test_production_handoff_is_eligible_before_artifacts_and_before_submission
    %w[cloud_running artifacts_verified archived].each do |state|
      manifest = release_manifest(state: state)
      release = release_for(manifest)
      if state == "archived"
        release = release.merge("assets" => release_assets(manifest))
      end
      result = validate(manifest, release: release)

      assert_equal true, result.fetch("eligible"), state
      assert_equal "production", result.fetch("channel")
      assert_equal 100, result.fetch("github_release_id")
      assert_equal "d" * 40, result.fetch("release_commit_sha")
    end
  end

  def test_completed_or_failed_handoffs_are_not_reprocessed
    %w[submitted live failed].each do |state|
      manifest = release_manifest(state: state)
      release = release_for(manifest)
      if %w[submitted live].include?(state)
        release = release.merge("assets" => release_assets(manifest))
      end
      result = validate(manifest, release: release)

      assert_equal false, result.fetch("eligible"), state
    end
  end

  def test_archived_beta_is_complete_and_not_reprocessed
    manifest = release_manifest(state: "archived", channel: "beta")

    release = release_for(manifest).merge("assets" => release_assets(manifest))
    result = validate(manifest, release: release)

    assert_equal false, result.fetch("eligible")
    assert_equal 2, result.fetch("artifact_names").length
  end

  def test_rejects_a_moved_tag_changed_title_or_unexpected_asset
    manifest = release_manifest
    assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest), ref_sha: "e" * 40)
    end

    changed_title = release_for(manifest).merge("name" => "changed")
    assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: changed_title)
    end

    unexpected_asset = release_for(manifest).merge("assets" => [{ "name" => "unexpected.zip" }])
    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: unexpected_asset)
    end
    assert_includes error.message, "unexpected artifacts"
  end

  def test_rejects_changed_release_notes_during_a_normal_handoff
    manifest = release_manifest
    changed = release_for(manifest).merge("body" => "changed")

    error = assert_raises(SequelAceRelease::ValidationError) { validate(manifest, release: changed) }

    assert_includes error.message, "release notes"
  end

  def test_rejects_a_release_not_authored_by_the_dedicated_app
    manifest = release_manifest
    release = release_for(manifest).merge("author" => { "login" => "Jason-Morcos" })

    error = assert_raises(SequelAceRelease::ValidationError) { validate(manifest, release: release) }

    assert_includes error.message, "dedicated release App"
  end

  def test_rejects_a_draft_or_different_tag_release
    manifest = release_manifest

    draft_error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest).merge("draft" => true))
    end
    assert_includes draft_error.message, "draft"

    tag_error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest).merge("tag_name" => "production/9.9.9-99999"))
    end
    assert_includes tag_error.message, "tag identity"
  end

  def test_rejects_a_release_commit_that_is_not_on_current_main
    manifest = release_manifest
    target_error = SequelAceRelease::ValidationError.new("release target is no longer an ancestor of current main")

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest), target_error: target_error)
    end

    assert_includes error.message, "ancestor"
  end

  def test_revalidates_release_commit_ancestry_and_protected_paths
    manifest = release_manifest
    github = GitHub.new(release: release_for(manifest))

    validate(manifest, release: release_for(manifest), github: github)

    assert_equal "d" * 40, github.target_arguments.fetch(:target_sha)
    assert_includes github.target_arguments.fetch(:protected_paths), "CHANGELOG.md"
    assert_includes github.target_arguments.fetch(:protected_paths), "sequel-ace.xcodeproj/project.pbxproj"
  end

  def test_rejects_app_store_notes_that_do_not_match_the_approved_body_section
    manifest = release_manifest

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest), app_store_notes: "Different notes")
    end

    assert_includes error.message, "App Store notes"
  end

  def test_rejects_a_malformed_or_duplicated_app_store_notes_section
    manifest = release_manifest
    malformed = release_for(manifest).merge(
      "body" => "#{BODY}#{BODY}",
    )
    manifest = manifest.with("release_notes_sha256" => Digest::SHA256.hexdigest(malformed.fetch("body")))

    error = assert_raises(SequelAceRelease::ValidationError) { validate(manifest, release: malformed) }

    assert_includes error.message, "one canonical"
  end

  def test_alpha_recovery_allows_only_a_known_failure_suffix
    manifest = release_manifest(channel: "beta")
    manifest = with_alpha_retry(manifest)
    annotated = release_for(manifest).merge(
      "body" => "#{BODY}\nAlpha-only recovery attempt stopped; the beta tag and existing artifacts were not replaced.\n" \
                "Workflow evidence: https://github.com/Sequel-Ace/Sequel-Ace/actions/runs/12345\n"
    )

    result = validate(manifest, release: annotated)

    assert_equal true, result.fetch("eligible")
    assert_equal true, result.fetch("alpha_recovery")
  end

  def test_alpha_recovery_rejects_an_arbitrary_body_change
    manifest = with_alpha_retry(release_manifest(channel: "beta"))
    annotated = release_for(manifest).merge("body" => "#{BODY}\nUnapproved annotation.\n")

    error = assert_raises(SequelAceRelease::ValidationError) { validate(manifest, release: annotated) }

    assert_includes error.message, "release notes"
  end

  def test_alpha_recovery_requires_structured_evidence_bound_to_the_release
    manifest = release_manifest(channel: "beta").with(
      "alpha_retry" => { "id" => "retry-run-id" },
      "cloud_build_ids" => { "alpha" => "different-run-id" }
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest))
    end

    assert_includes error.message, "Alpha recovery evidence"
  end

  def test_alpha_recovery_rejects_a_predecessor_that_does_not_match_the_durable_failure
    manifest = with_alpha_retry(release_manifest(channel: "beta")).with(
      "alpha_retry_predecessor" => {
        "durable_failed_run_id" => "different-run-id",
        "authorized_failed_run_id" => "failed-run-id"
      }
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest))
    end

    assert_includes error.message, "durable failed run"
  end

  def test_archived_handoff_requires_every_expected_public_asset
    manifest = release_manifest(state: "archived")

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest))
    end

    assert_includes error.message, "missing artifacts"
  end

  def test_archived_handoff_rejects_a_same_name_asset_with_the_wrong_digest
    manifest = release_manifest(state: "archived")
    assets = release_assets(manifest)
    assets.first["digest"] = "sha256:#{'f' * 64}"

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest).merge("assets" => assets))
    end

    assert_includes error.message, "checksum mismatch"
  end

  def test_archived_handoff_requires_a_well_formed_checksum_for_every_asset
    manifest = release_manifest(state: "archived").with("verification" => {})

    error = assert_raises(SequelAceRelease::ValidationError) do
      validate(manifest, release: release_for(manifest).merge("assets" => release_assets(release_manifest(state: "archived"))))
    end

    assert_includes error.message, "missing artifact checksums"
  end

  private

  def validate(
    manifest, release:, ref_sha: "d" * 40, target_error: nil,
    github: nil, app_store_notes: APP_STORE_NOTES
  )
    github ||= GitHub.new(release: release, ref_sha: ref_sha, target_error: target_error)
    SequelAceRelease::PublishHandoff.new(github: github).validate(
      manifest: manifest,
      tag: manifest.to_h.fetch("tag"),
      app_store_notes: app_store_notes
    )
  end

  def release_manifest(state: "cloud_running", channel: "production")
    release_approval = approval(
      channel: channel,
      release_notes_sha256: Digest::SHA256.hexdigest(BODY)
    )
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: channel,
      version: "5.3.2",
      build: 20_105,
      iteration: 1
    )
    SequelAceRelease::Manifest.create(
      approval: release_approval,
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_105,
      release_notes_sha256: Digest::SHA256.hexdigest(BODY),
      state: state
    ).with("release_commit_sha" => "d" * 40).then do |manifest|
      durable_state?(state) ? manifest.with("verification" => verification_for(manifest)) : manifest
    end
  end

  def release_for(manifest)
    {
      "id" => 100,
      "tag_name" => manifest.to_h.fetch("tag"),
      "name" => manifest.to_h.fetch("title"),
      "draft" => false,
      "prerelease" => true,
      "body" => BODY,
      "author" => { "login" => SequelAceRelease::PublishHandoff::RELEASE_APP_LOGIN },
      "assets" => []
    }
  end

  def with_alpha_retry(manifest)
    retry_run = {
      "id" => "retry-run-id",
      "workflow_id" => "alpha-workflow-id",
      "git_reference" => manifest.to_h.fetch("tag"),
      "source_commit" => manifest.to_h.fetch("release_commit_sha"),
      "reused_existing_retry" => false
    }
    manifest.with(
      "alpha_retry" => retry_run,
      "alpha_retry_predecessor" => {
        "durable_failed_run_id" => "failed-run-id",
        "authorized_failed_run_id" => "failed-run-id"
      },
      "failure" => { "component" => "alpha", "cloud_run_id" => "failed-run-id" },
      "cloud_build_ids" => manifest.to_h.fetch("cloud_build_ids").merge("alpha" => retry_run.fetch("id"))
    )
  end

  def durable_state?(state)
    %w[archived submitted live].include?(state)
  end

  def verification_for(manifest)
    manifest.to_h.fetch("artifact_names").each_with_index.to_h do |name, index|
      channel = index.zero? ? "production" : "alpha"
      [channel, { "zip_path" => "/tmp/#{name}", "zip_sha256" => digest_for(name) }]
    end
  end

  def release_assets(manifest)
    manifest.to_h.fetch("artifact_names").map do |name|
      { "name" => name, "digest" => "sha256:#{digest_for(name)}" }
    end
  end

  def digest_for(name)
    Digest::SHA256.hexdigest(name)
  end
end
