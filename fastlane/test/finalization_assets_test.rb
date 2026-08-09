# frozen_string_literal: true

require "test_helper"

class FinalizationAssetsTest < Minitest::Test
  def setup
    @cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    @body = "## App Store Release Notes\n\nA focused update.\n"
    @digest = "a" * 64
  end

  def test_exact_release_body_asset_set_and_archived_checksum_pass
    assert @cli.send(:verify_release_assets!, release, manifest)
  end

  def test_unexpected_public_asset_aborts
    value = release
    value["assets"] << { "name" => "unexpected.zip", "digest" => "sha256:#{'b' * 64}" }

    error = assert_raises(SequelAceRelease::ValidationError) do
      @cli.send(:verify_release_assets!, value, manifest)
    end
    assert_includes error.message, "unexpected artifacts"
  end

  def test_missing_archived_checksum_aborts
    value = manifest
    value["verification"] = {}

    error = assert_raises(SequelAceRelease::ValidationError) do
      @cli.send(:verify_release_assets!, release, value)
    end
    assert_includes error.message, "missing artifact checksums"
  end

  def test_validate_only_does_not_make_the_public_github_transition
    live_snapshot = metadata_snapshot(state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) do |app_id:, version:|
      raise "wrong app" unless app_id == SequelAceRelease::Config::PRODUCTION_APP_ID
      raise "wrong version" unless version == "5.3.2"

      live_snapshot
    end
    release_data = release
    github = Object.new
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:update_release) { |**_options| raise "validate-only mutated GitHub" }

    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      output_path = File.join(directory, "finalization-validation.json")
      release_manifest.write(manifest_path)
      status = @cli.stub(:app_store_client, app_store) do
        @cli.stub(:github_client, github) do
          @cli.run([
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20105",
            "--validate-only",
            "--output", output_path
          ])
        end
      end

      assert_equal 0, status
      evidence = JSON.parse(File.read(output_path))
      assert_equal "durably_validated_before_public_transition", evidence.fetch("github_transition")
      assert_equal true, evidence.fetch("transition_required")
      assert_equal "5.3.2 (20105)", evidence.fetch("target_title")
    end
  end

  private

  def release
    {
      "id" => 100,
      "name" => "5.3.2 (20105) - Release Candidate 1",
      "prerelease" => true,
      "body" => @body,
      "assets" => [{ "name" => "Sequel-Ace-5.3.2.zip", "digest" => "sha256:#{@digest}" }]
    }
  end

  def release_manifest
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 1
    )
    SequelAceRelease::Manifest.create(
      approval: approval(release_notes_sha256: Digest::SHA256.hexdigest(@body)),
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_105,
      release_notes_sha256: Digest::SHA256.hexdigest(@body),
      state: "submitted"
    ).with("verification" => manifest.fetch("verification"))
  end

  def manifest
    {
      "release_notes_sha256" => Digest::SHA256.hexdigest(@body),
      "artifact_names" => ["Sequel-Ace-5.3.2.zip"],
      "verification" => {
        "production" => {
          "zip_path" => "/runner/artifacts/Sequel-Ace-5.3.2.zip",
          "zip_sha256" => @digest
        }
      }
    }
  end
end
