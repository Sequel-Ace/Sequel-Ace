# frozen_string_literal: true

require "test_helper"

class ApprovalManifestTest < Minitest::Test
  def test_approval_hash_is_canonical_and_detects_changes
    release_approval = approval
    assert release_approval.verify!(release_approval.sha256)

    changed = approval(app_store_notes: "Different notes")
    refute_equal release_approval.sha256, changed.sha256
    assert_raises(SequelAceRelease::ValidationError) { changed.verify!(release_approval.sha256) }
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

    Dir.mktmpdir do |directory|
      path = File.join(directory, "manifest.json")
      manifest.write(path)
      loaded = SequelAceRelease::Manifest.read(path)
      assert_equal manifest.to_h, loaded.to_h
      assert_equal "planned", loaded.to_h.fetch("state")
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
