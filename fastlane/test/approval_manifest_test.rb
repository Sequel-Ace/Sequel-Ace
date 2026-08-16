# frozen_string_literal: true

require "test_helper"

class ApprovalManifestTest < Minitest::Test
  def test_approval_hash_is_canonical_and_detects_changes
    release_approval = approval
    assert release_approval.verify!(release_approval.sha256)

    changed = approval(app_store_notes: "Different notes")
    refute_equal release_approval.sha256, changed.sha256
    assert_raises(SequelAceRelease::ValidationError) { changed.verify!(release_approval.sha256) }

    changed_base = approval(base_sha: "d" * 40)
    refute_equal release_approval.sha256, changed_base.sha256
    assert_raises(SequelAceRelease::ValidationError) { changed_base.verify!(release_approval.sha256) }

    changed_changelog_base = approval(
      changelog_base_tag: "production/5.3.0-20103",
      changelog_base_sha: "e" * 40
    )
    refute_equal release_approval.sha256, changed_changelog_base.sha256
    assert_raises(SequelAceRelease::ValidationError) do
      changed_changelog_base.verify!(release_approval.sha256)
    end

    changed_release_body = approval(release_notes_sha256: "d" * 64)
    refute_equal release_approval.sha256, changed_release_body.sha256
    assert_raises(SequelAceRelease::ValidationError) do
      changed_release_body.verify!(release_approval.sha256)
    end

    changed_policy = release_approval.to_h.merge("build_policy" => "different-policy").reject { |key, _| key == "sha256" }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(changed_policy)
    end

    missing_base = release_approval.to_h.reject { |key, _| %w[sha256 base_sha].include?(key) }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_base)
    end

    missing_changelog_base = release_approval.to_h.reject do |key, _|
      %w[sha256 changelog_base_tag changelog_base_sha].include?(key)
    end
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_changelog_base)
    end

    missing_body = release_approval.to_h.reject { |key, _| %w[sha256 release_notes_sha256].include?(key) }
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(missing_body)
    end

  end

  def test_approval_normalizes_valid_git_shas_and_rejects_invalid_lengths
    uppercase = approval(
      main_sha: "A" * 40,
      base_sha: "B" * 40,
      changelog_base_sha: "B" * 40
    )
    lowercase = approval

    assert_equal lowercase.payload.fetch("main_sha"), uppercase.payload.fetch("main_sha")
    assert_equal lowercase.sha256, uppercase.sha256
    assert_raises(SequelAceRelease::ValidationError) { approval(main_sha: "a" * 41) }
    assert_raises(SequelAceRelease::ValidationError) do
      approval(previous_tag: "production/5.3.1-0")
    end
  end

  def test_validated_approval_payload_cannot_be_mutated
    source_notes = +"A focused release note."
    release_approval = approval(app_store_notes: source_notes)
    payload = release_approval.payload

    assert payload.frozen?
    assert payload.fetch("app_store_notes").frozen?
    refute source_notes.frozen?
    assert_raises(FrozenError) { payload["channel"] = "beta" }
    assert_raises(FrozenError) { payload.fetch("app_store_notes").replace("changed") }
    assert release_approval.verify!(release_approval.sha256)
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
        production_build_evidence: production_build_evidence,
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
        production_build_evidence: production_build_evidence,
        release_notes_sha256: "e" * 64
      )
    end
    assert_includes error.message, "release body does not match"
  end

  def test_manifest_allows_runtime_iteration_to_advance_without_changing_approval
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 2
    )

    manifest = SequelAceRelease::Manifest.create(
      approval: approval,
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_105,
      production_build_evidence: production_build_evidence,
      release_notes_sha256: "c" * 64
    )
    assert_equal 2, manifest.to_h.fetch("iteration")
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
      production_build_evidence: production_build_evidence,
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
      assert_equal SequelAceRelease::Approval::POLICY, loaded.to_h.fetch("build_policy")
      assert_equal 20_105, loaded.to_h.dig("production_build_evidence", "expected_next_build")
      assert_equal "production/5.3.1-20104", loaded.to_h.fetch("changelog_base_tag")
      assert_equal "b" * 40, loaded.to_h.fetch("changelog_base_sha")
    end
  end

  def test_notes_limit_is_enforced
    assert_raises(SequelAceRelease::ValidationError) do
      approval(app_store_notes: "x" * 4_001)
    end
  end

  def test_schema_one_archives_remain_readable_during_an_in_flight_upgrade
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 1
    )
    current = SequelAceRelease::Manifest.create(
      approval: approval,
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_105,
      production_build_evidence: production_build_evidence,
      release_notes_sha256: "c" * 64
    ).to_h
    legacy = current.merge(
      "schema_version" => 1,
      "observed_production_cloud_next_build" => 20_105
    ).reject { |key, _| %w[build_policy production_build_evidence].include?(key) }

    assert_equal legacy, SequelAceRelease::Manifest.new(legacy).to_h
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
    release = github_release_payload(
      tag: "production/5.3.2-20109",
      body: body,
      assets: [github_release_asset(name: "Sequel-Ace-5.3.2.zip", digest: digest)]
    )
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    github = Object.new
    github.define_singleton_method(:public_release_feed_page) { [release] }

    assert cli.send(:verify_release_assets!, release, manifest, github: github)
    release["body"] = "changed"
    assert_raises(SequelAceRelease::ValidationError) do
      cli.send(:verify_release_assets!, release, manifest, github: github)
    end
  end

  private

  def production_build_evidence
    {
      "policy" => SequelAceRelease::Approval::POLICY,
      "source_build" => 20_104,
      "highest_tag_build" => 20_104,
      "highest_asc_build" => 20_104,
      "highest_cloud_build" => 20_104,
      "highest_observed_build" => 20_104,
      "expected_next_build" => 20_105
    }
  end
end
