# frozen_string_literal: true

require "test_helper"

class LegacyReleasePayloadTest < Minitest::Test
  def setup
    @name = "Sequel-Ace-5.4.0.zip"
    @digest = Digest::SHA256.hexdigest("verified release bytes")
  end

  def test_accepts_the_exact_legacy_compatible_web_upload_shape
    result = validate(release)

    assert_equal true, result.fetch("ready")
    assert_equal "manual_web_upload", result.fetch("mode")
    assert_equal true, result.fetch("legacy_compatibility_required")
    assert_empty result.fetch("missing_assets")
  end

  def test_reports_a_missing_legacy_asset_without_mutating_github
    result = validate(release.merge("assets" => []))

    assert_equal false, result.fetch("ready")
    assert_equal "manual_web_upload", result.fetch("mode")
    assert_equal [@name], result.fetch("missing_assets")
  end

  def test_rejects_the_empty_label_returned_by_rest_uploads
    incompatible = release
    incompatible["assets"].first["label"] = ""

    error = assert_raises(SequelAceRelease::IntegrityError) { validate(incompatible) }

    assert_includes error.message, "JSON null"
  end

  def test_rejects_a_bot_asset_uploader_even_on_a_prerelease
    incompatible = release
    incompatible["prerelease"] = true
    incompatible["assets"].first["uploader"] = {
      "login" => "sequel-ace-release-automation[bot]",
      "id" => 4_541_115,
      "node_id" => "BOT_node",
      "type" => "Bot"
    }

    error = assert_raises(SequelAceRelease::IntegrityError) { validate(incompatible) }

    assert_includes error.message, "legacy Sequel Ace clients"
  end

  def test_rejects_a_user_with_the_right_login_but_changed_enum_fields
    incompatible = release
    incompatible["assets"].first["uploader"]["node_id"] = "different"

    error = assert_raises(SequelAceRelease::IntegrityError) { validate(incompatible) }

    assert_includes error.message, "identity is incompatible"
  end

  def test_rejects_wrong_content_type_state_checksum_duplicates_and_unexpected_assets
    candidates = []
    candidates << release.tap { |value| value["assets"].first["content_type"] = "application/octet-stream" }
    candidates << release.tap { |value| value["assets"].first["state"] = "new" }
    candidates << release.tap { |value| value["assets"].first["digest"] = "sha256:#{'0' * 64}" }
    candidates << release.tap { |value| value["assets"] << value["assets"].first.dup }
    candidates << release.tap do |value|
      value["assets"] << compatible_asset.merge("name" => "unexpected.zip")
    end

    candidates.each do |candidate|
      assert_raises(SequelAceRelease::IntegrityError) { validate(candidate) }
    end
  end

  def test_rejects_malformed_asset_metadata_without_sorting_untrusted_values
    [nil, {}, { "name" => nil }, { "name" => "" }].each do |asset|
      error = assert_raises(SequelAceRelease::IntegrityError) do
        validate(release.merge("assets" => [asset]))
      end
      assert_includes error.message, "metadata is malformed"
    end
  end

  def test_allows_the_release_app_epoch_without_legacy_author_or_label_constraints
    modern = release.merge(
      "created_at" => "2027-08-14T00:00:00Z",
      "author" => { "login" => "sequel-ace-release-automation[bot]", "type" => "Bot" },
      "assets" => [compatible_asset.merge(
        "label" => "",
        "uploader" => { "login" => "sequel-ace-release-automation[bot]", "type" => "Bot" }
      )]
    )

    result = validate(modern)

    assert_equal true, result.fetch("ready")
    assert_equal "api_upload", result.fetch("mode")
    assert_equal false, result.fetch("legacy_compatibility_required")
  end

  private

  def validate(value)
    SequelAceRelease::LegacyReleasePayload.new(
      release: value,
      expected_digests: { @name => @digest }
    ).validate
  end

  def release
    {
      "id" => 370_232_757,
      "tag_name" => "production/5.4.0-20109",
      "created_at" => "2026-08-13T00:00:00Z",
      "author" => legacy_author,
      "draft" => false,
      "prerelease" => false,
      "assets" => [compatible_asset]
    }
  end

  def compatible_asset
    {
      "id" => 515_968_456,
      "name" => @name,
      "label" => nil,
      "uploader" => legacy_author,
      "content_type" => "application/zip",
      "state" => "uploaded",
      "digest" => "sha256:#{@digest}"
    }
  end

  def legacy_author
    {
      "login" => "Jason-Morcos",
      "id" => 10_710_367,
      "node_id" => "MDQ6VXNlcjEwNzEwMzY3",
      "type" => "User",
      "following_url" => "https://api.github.com/users/Jason-Morcos/following{/other_user}",
      "gists_url" => "https://api.github.com/users/Jason-Morcos/gists{/gist_id}",
      "starred_url" => "https://api.github.com/users/Jason-Morcos/starred{/owner}{/repo}",
      "events_url" => "https://api.github.com/users/Jason-Morcos/events{/privacy}"
    }
  end
end
