# frozen_string_literal: true

require "test_helper"

class ApprovalManifestTest < Minitest::Test
  def test_approval_hash_is_canonical_and_detects_changes
    release_approval = approval
    assert release_approval.verify!(release_approval.sha256)

    changed = approval(app_store_notes: "Different notes")
    refute_equal release_approval.sha256, changed.sha256
    assert_raises(SequelAceRelease::ValidationError) { changed.verify!(release_approval.sha256) }

    changed_build = approval(observed_production_cloud_next_build: 20_106)
    refute_equal release_approval.sha256, changed_build.sha256
    assert_raises(SequelAceRelease::ValidationError) { changed_build.verify!(release_approval.sha256) }

    changed_base = approval(base_sha: "d" * 40)
    refute_equal release_approval.sha256, changed_base.sha256
    assert_raises(SequelAceRelease::ValidationError) { changed_base.verify!(release_approval.sha256) }

    changed_release_body = approval(release_notes_sha256: "d" * 64)
    refute_equal release_approval.sha256, changed_release_body.sha256
    assert_raises(SequelAceRelease::ValidationError) do
      changed_release_body.verify!(release_approval.sha256)
    end

    changed_iteration = approval(release_iteration: 2)
    refute_equal release_approval.sha256, changed_iteration.sha256
    assert_raises(SequelAceRelease::ValidationError) do
      changed_iteration.verify!(release_approval.sha256)
    end

    missing_build = release_approval.to_h.reject { |key, _| %w[sha256 observed_production_cloud_next_build].include?(key) }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_build)
    end

    missing_base = release_approval.to_h.reject { |key, _| %w[sha256 base_sha].include?(key) }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_base)
    end

    missing_body = release_approval.to_h.reject { |key, _| %w[sha256 release_notes_sha256].include?(key) }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_body)
    end

    missing_iteration = release_approval.to_h.reject { |key, _| %w[sha256 release_iteration].include?(key) }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_iteration)
    end
  end

  def test_manifest_rejects_a_base_sha_outside_the_approval
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 1
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Manifest.create(
        approval: approval,
        naming: naming,
        base_sha: "e" * 40,
        canonical_build: 20_105,
        release_notes_sha256: "c" * 64
      )
    end
    assert_includes error.message, "immutable approval"
  end

  def test_manifest_rejects_a_release_body_outside_the_approval
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 1
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Manifest.create(
        approval: approval,
        naming: naming,
        base_sha: "b" * 40,
        canonical_build: 20_105,
        release_notes_sha256: "e" * 64
      )
    end
    assert_includes error.message, "release body does not match"
  end

  def test_manifest_rejects_an_iteration_outside_the_approval
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 2
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Manifest.create(
        approval: approval,
        naming: naming,
        base_sha: "b" * 40,
        canonical_build: 20_105,
        release_notes_sha256: "c" * 64
      )
    end
    assert_includes error.message, "iteration does not match"
  end

  def test_manifest_round_trip
    release_approval = approval
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 1
    )
    manifest = SequelAceRelease::Manifest.create(
      approval: release_approval,
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_105,
      release_notes_sha256: "c" * 64
    )
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Manifest.new(manifest.to_h.merge("release_commit_sha" => "not-a-sha"))
    end

    Dir.mktmpdir do |directory|
      path = File.join(directory, "manifest.json")
      manifest.write(path)
      loaded = SequelAceRelease::Manifest.read(path)
      assert_equal manifest.to_h, loaded.to_h
      assert_equal "planned", loaded.to_h.fetch("state")
      assert_equal 20_105, loaded.to_h.fetch("observed_production_cloud_next_build")
    end
  end

  def test_notes_limit_is_enforced
    assert_raises(SequelAceRelease::ValidationError) do
      approval(app_store_notes: "x" * 4_001)
    end
  end

  def test_finalization_integrity_requires_the_archived_body_and_asset_checksum
    body = "## App Store Release Notes\n\nA focused release note.\n"
    digest = "d" * 64
    manifest = {
      "release_notes_sha256" => Digest::SHA256.hexdigest(body),
      "artifact_names" => ["Sequel-Ace-5.3.2.zip"],
      "verification" => {
        "production" => {
          "zip_path" => "/runner/Sequel-Ace-5.3.2.zip",
          "zip_sha256" => digest
        }
      }
    }
    release = {
      "body" => body,
      "assets" => [{ "name" => "Sequel-Ace-5.3.2.zip", "digest" => "sha256:#{digest}" }]
    }
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

    assert cli.send(:verify_release_assets!, release, manifest)
    release["body"] = "changed"
    assert_raises(SequelAceRelease::ValidationError) do
      cli.send(:verify_release_assets!, release, manifest)
    end
  end
end
