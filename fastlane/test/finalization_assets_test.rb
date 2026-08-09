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

  private

  def release
    {
      "body" => @body,
      "assets" => [{ "name" => "Sequel-Ace-5.3.2.zip", "digest" => "sha256:#{@digest}" }]
    }
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
