# frozen_string_literal: true

require "test_helper"

class GitHubReleasePayloadTest < Minitest::Test
  def setup
    @name = "Sequel-Ace-5.4.0.zip"
    @digest = Digest::SHA256.hexdigest("verified release bytes")
  end

  def test_selects_legacy_profile_from_payload_capability_not_date_or_build
    old_tagged_bot_release = modern_release.merge(
      "tag_name" => "production/1.0.0-1",
      "created_at" => "2020-01-01T00:00:00Z"
    )
    future_user_release = release.merge(
      "tag_name" => "production/99.0.0-99999",
      "created_at" => "2035-01-01T00:00:00Z",
      "published_at" => "2035-01-01T00:00:00Z"
    )

    assert_equal "github_api_v1", validate(old_tagged_bot_release).fetch("compatibility_profile")
    assert_equal "legacy_updater_v1", validate(future_user_release).fetch("compatibility_profile")
  end

  def test_accepts_complete_legacy_shapes_for_both_historical_enum_users
    ["Jason-Morcos", "Kaspik"].each do |login|
      user = legacy_github_user(login: login)
      compatible = github_release_payload(
        author: user,
        assets: [compatible_asset.merge("uploader" => user, "future_github_field" => { "ignored" => true })]
      ).merge("future_github_field" => "ignored")

      result = validate(compatible)

      assert_equal true, result.fetch("ready"), login
      assert_equal "manual_web_upload", result.fetch("mode"), login
      assert_equal %w[Jason-Morcos Kaspik].sort, result.fetch("compatible_uploaders"), login
    end
  end

  def test_reports_a_missing_legacy_asset_without_mutating_github
    result = validate(release.merge("assets" => []))

    assert_equal false, result.fetch("ready")
    assert_equal "manual_web_upload", result.fetch("mode")
    assert_equal [@name], result.fetch("missing_assets")
  end

  def test_rejects_the_empty_label_returned_by_rest_uploads_for_a_legacy_profile
    incompatible = release
    incompatible["assets"].first["label"] = ""

    error = assert_raises(SequelAceRelease::IntegrityError) { validate(incompatible) }

    assert_includes error.message, "JSON null"
  end

  def test_rejects_an_uploader_that_the_shipped_decoder_cannot_decode
    incompatible = release
    incompatible["assets"].first["uploader"] = {
      "login" => "sequel-ace-release-automation[bot]",
      "id" => SequelAceRelease::ReleasePublisher::RELEASE_APP_BOT_ID,
      "type" => "Bot"
    }

    error = assert_raises(SequelAceRelease::IntegrityError) { validate(incompatible) }

    assert_includes error.message, "legacy clients"
  end

  def test_rejects_changed_enum_fields_but_not_unrelated_github_fields
    incompatible = release
    incompatible["assets"].first["uploader"]["node_id"] = "different"

    error = assert_raises(SequelAceRelease::IntegrityError) { validate(incompatible) }

    assert_includes error.message, "identity is incompatible"
  end

  def test_validates_every_primitive_that_the_shipped_decoder_requires
    candidates = []
    candidates << release.tap { |value| value.delete("published_at") }
    candidates << release.tap { |value| value["author"].delete("site_admin") }
    candidates << release.tap { |value| value["assets"].first.delete("browser_download_url") }
    candidates << release.tap { |value| value["assets"].first["download_count"] = -1 }
    candidates << release.tap { |value| value["assets"].first["created_at"] = "not-a-date" }

    candidates.each do |candidate|
      error = assert_raises(SequelAceRelease::IntegrityError) { validate(candidate) }
      assert_match(/legacy clients|metadata is malformed/, error.message)
    end
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

  def test_api_profile_ignores_uploader_label_and_future_metadata
    asset = compatible_asset
    asset.delete("label")
    asset.delete("uploader")
    asset["future_github_field"] = [1, 2, 3]
    compatible = modern_release.merge(
      "assets" => [asset],
      "future_github_field" => { "nested" => true }
    )

    result = validate(compatible)

    assert_equal true, result.fetch("ready")
    assert_equal "api_upload", result.fetch("mode")
    assert_equal "github_api_v1", result.fetch("compatibility_profile")
    assert_empty result.fetch("compatible_uploaders")
  end

  def test_legacy_profile_validates_every_release_visible_to_shipped_clients
    validator = payload_validator(release)
    other = github_release_payload(
      id: 101,
      tag: "production/5.3.1-20104",
      assets: [github_release_asset(name: "Sequel-Ace-5.3.1.zip", digest: "f" * 64)]
    )

    assert_equal 2, validator.validate_public_feed!([release, other])

    incompatible = other.merge("author" => modern_release.fetch("author"))
    error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([release, incompatible])
    end
    assert_includes error.message, "entry 2"
    assert_includes error.message, "legacy-decodable"
  end

  def test_public_feed_must_include_the_exact_release
    validator = payload_validator(release)
    other = github_release_payload(id: 101, tag: "production/5.3.1-20104")

    error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([other])
    end

    assert_includes error.message, "exact GitHub release is absent"
  end

  def test_public_feed_target_must_contain_the_exact_public_asset_set_and_digests
    validator = payload_validator(release)

    missing_error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([release.merge("assets" => [])])
    end
    assert_includes missing_error.message, "missing artifacts"

    stale_asset = compatible_asset.merge("digest" => "sha256:#{'0' * 64}")
    checksum_error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([release.merge("assets" => [stale_asset])])
    end
    assert_includes checksum_error.message, "checksum mismatch"
  end

  def test_public_feed_target_must_match_updater_consumed_authenticated_fields
    authenticated = release.merge(
      "name" => "5.4.0 (20109)",
      "prerelease" => false
    )
    validator = payload_validator(authenticated)
    candidates = []
    candidates << authenticated.merge("name" => "5.4.0 (20109) - Release Candidate 1")
    candidates << authenticated.merge("draft" => true)
    candidates << authenticated.merge("prerelease" => true)
    candidates << authenticated.merge("html_url" => "https://github.com/Sequel-Ace/Sequel-Ace/releases/stale")
    candidates << authenticated.merge("published_at" => "2026-08-12T00:00:00Z")
    candidates << authenticated.merge(
      "assets" => [authenticated.fetch("assets").first.merge("id" => 999)]
    )
    candidates << authenticated.merge(
      "assets" => [authenticated.fetch("assets").first.merge("size" => 41)]
    )
    candidates << authenticated.merge(
      "assets" => [authenticated.fetch("assets").first.merge(
        "browser_download_url" => "https://github.com/Sequel-Ace/Sequel-Ace/releases/download/stale/app.zip"
      )]
    )

    candidates.each do |candidate|
      error = assert_raises(SequelAceRelease::IntegrityError) do
        validator.validate_public_feed!([candidate])
      end
      assert_includes error.message, "authenticated and anonymous responses"
    end
  end

  def test_public_feed_rejects_duplicate_target_identities
    validator = payload_validator(release)

    error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([release, release.dup])
    end

    assert_includes error.message, "appears more than once"
  end

  def test_api_profile_requires_exact_anonymous_visibility_without_decoding_unrelated_entries
    authenticated = modern_release
    validator = payload_validator(authenticated)
    unrelated_future_release = { "future_shape" => [1, 2, 3] }

    assert_equal 2, validator.validate_public_feed!([authenticated, unrelated_future_release])

    missing_error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([unrelated_future_release])
    end
    assert_includes missing_error.message, "absent from the public release feed"

    stale_error = assert_raises(SequelAceRelease::IntegrityError) do
      validator.validate_public_feed!([authenticated.merge("assets" => [])])
    end
    assert_includes stale_error.message, "missing artifacts"
  end

  def test_api_profile_public_target_must_match_authenticated_author_identity
    authenticated = modern_release
    anonymous = authenticated.merge(
      "author" => authenticated.fetch("author").merge("login" => "renamed-release-bot")
    )

    error = assert_raises(SequelAceRelease::IntegrityError) do
      payload_validator(authenticated).validate_public_feed!([anonymous])
    end

    assert_includes error.message, "author field login"
    assert_includes error.message, "authenticated and anonymous responses"
  end

  def test_api_profile_rejects_malformed_updater_consumed_target_fields
    candidates = []
    candidates << modern_release.merge("html_url" => nil)
    candidates << modern_release.merge("published_at" => "not-a-date")
    candidates << modern_release.merge(
      "assets" => [compatible_asset.merge("size" => 0)]
    )
    candidates << modern_release.merge(
      "assets" => [compatible_asset.merge("browser_download_url" => "")]
    )

    candidates.each do |candidate|
      error = assert_raises(SequelAceRelease::IntegrityError) do
        payload_validator(candidate).validate_public_feed!([candidate])
      end
      assert_includes error.message, "metadata is malformed"
    end
  end

  private

  def validate(value)
    payload_validator(value).validate
  end

  def payload_validator(value)
    SequelAceRelease::GitHubReleasePayload.new(
      release: value,
      expected_digests: { @name => @digest }
    )
  end

  def release
    github_release_payload(assets: [compatible_asset])
  end

  def modern_release
    github_release_payload(
      author: {
        "login" => "sequel-ace-release-automation[bot]",
        "id" => SequelAceRelease::ReleasePublisher::RELEASE_APP_BOT_ID,
        "type" => "Bot"
      },
      assets: [compatible_asset]
    )
  end

  def compatible_asset
    github_release_asset(name: @name, digest: @digest)
  end
end
