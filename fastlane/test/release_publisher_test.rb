# frozen_string_literal: true

require "test_helper"

class ReleasePublisherTest < Minitest::Test
  def test_authorizes_stable_numeric_identities_without_date_or_build_epochs
    %w[
      production/1.0.0-1
      beta/5.5.0-20110
      production/99.0.0-99999
    ].each do |tag|
      assert SequelAceRelease::ReleasePublisher.authorized?(
        tag: tag,
        login: "renamed-maintainer",
        id: SequelAceRelease::ReleasePublisher::USER_ID,
        created_at: "2035-01-01T00:00:00Z"
      ), tag
      assert SequelAceRelease::ReleasePublisher.authorized?(
        tag: tag,
        login: "renamed-release-app[bot]",
        id: SequelAceRelease::ReleasePublisher::RELEASE_APP_BOT_ID,
        created_at: "2020-01-01T00:00:00Z"
      ), tag
    end
  end

  def test_rejects_unrecognized_or_cross_kind_identities
    tag = "production/5.4.0-20109"

    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: tag,
      login: "Jason-Morcos",
      id: SequelAceRelease::ReleasePublisher::USER_ID + 1
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: tag,
      login: "sequel-ace-release-automation[bot]",
      id: SequelAceRelease::ReleasePublisher::USER_ID
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: tag,
      login: "Jason-Morcos",
      id: SequelAceRelease::ReleasePublisher::RELEASE_APP_BOT_ID
    )
  end

  def test_accepts_current_and_renamed_accounts_by_stable_id
    tag = "production/5.4.0-20109"

    assert SequelAceRelease::ReleasePublisher.authorized?(
      tag: tag,
      login: SequelAceRelease::ReleasePublisher::USER_LOGIN,
      id: SequelAceRelease::ReleasePublisher::USER_ID
    )
    assert SequelAceRelease::ReleasePublisher.authorized?(
      tag: tag,
      login: "renamed-maintainer",
      id: SequelAceRelease::ReleasePublisher::USER_ID
    )
    [SequelAceRelease::ReleasePublisher::RELEASE_APP_LOGIN, "renamed-release-app[bot]"].each do |login|
      assert SequelAceRelease::ReleasePublisher.authorized?(
        tag: tag,
        login: login,
        id: SequelAceRelease::ReleasePublisher::RELEASE_APP_BOT_ID
      )
    end
  end

  def test_rejects_malformed_tags_and_logins
    ["5.4.0", "production/5.4-1", "production/5.4.0-0"].each do |tag|
      refute SequelAceRelease::ReleasePublisher.authorized?(
        tag: tag,
        login: "Jason-Morcos",
        id: SequelAceRelease::ReleasePublisher::USER_ID
      )
    end
    [nil, "", "space in login", "bot[bot][bot]"].each do |login|
      refute SequelAceRelease::ReleasePublisher.authorized?(
        tag: "production/5.4.0-20109",
        login: login,
        id: SequelAceRelease::ReleasePublisher::USER_ID
      )
    end
  end

  def test_tag_validation_returns_only_a_well_formed_release_tag
    tag = "production/99.0.0-99999"

    assert_equal tag, SequelAceRelease::ReleasePublisher.validate_tag!(tag)
    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::ReleasePublisher.validate_tag!("production/latest")
    end
    assert_includes error.message, "release tag is malformed"
  end

  def test_validation_fails_closed
    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::ReleasePublisher.validate!(
        tag: "production/5.4.0-20109",
        login: "another-maintainer",
        id: 123
      )
    end

    assert_includes error.message, "not authorized"
  end

  def test_accepts_only_a_fine_grained_pat_for_the_user_publisher
    assert_equal "github_pat_example",
                 SequelAceRelease::ReleasePublisher.validate_user_publisher_token!("github_pat_example")

    [nil, "", "ghp_example", "gho_example", "ghu_example", "github_pat_"].each do |credential|
      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ReleasePublisher.validate_user_publisher_token!(credential)
      end
      assert_includes error.message, "fine-grained personal access token"
    end
  end
end
