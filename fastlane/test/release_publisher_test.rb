# frozen_string_literal: true

require "test_helper"

class ReleasePublisherTest < Minitest::Test
  def test_requires_jason_for_the_current_and_future_build_range
    %w[production/5.4.0-20109 beta/5.5.0-20110 production/6.0.0-99999].each do |tag|
      assert SequelAceRelease::ReleasePublisher.authorized?(
        tag: tag,
        login: "Jason-Morcos",
        at: Time.utc(2026, 8, 13)
      ), tag
    end
  end

  def test_rejects_cross_generation_and_unrecognized_publishers
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.4.0-20105",
      login: "Jason-Morcos"
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.4.0-20105",
      login: "sequel-ace-release-automation[bot]"
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.4.0-20109",
      login: "sequel-ace-release-automation[bot]",
      at: Time.utc(2027, 8, 13, 23, 59, 59)
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.4.0-20109",
      login: "another-maintainer",
      at: Time.utc(2027, 8, 14)
    )
  end

  def test_switches_new_release_creation_to_the_bot_at_the_pat_expiry_cutoff
    before = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF -
             SequelAceRelease::ReleasePublisher::USER_PUBLISHER_SAFETY_WINDOW - 1
    cutoff = Time.utc(2027, 8, 14)

    assert_equal :user, SequelAceRelease::ReleasePublisher.active_mode(at: before)
    assert_equal :app, SequelAceRelease::ReleasePublisher.active_mode(at: cutoff)
    assert SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.5.0-20110",
      login: "sequel-ace-release-automation[bot]",
      at: cutoff
    )
    assert SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.5.0-20110",
      login: "sequel-ace-releases[bot]",
      at: cutoff
    ), "renaming the same release App must not require a second App"
    assert SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.4.0-20109",
      login: "Jason-Morcos",
      created_at: "2026-08-13T00:00:00Z",
      at: cutoff
    ), "historical Jason-authored releases must remain verifiable after cutover"
  end

  def test_pauses_new_creation_during_the_cutoff_safety_window
    cutoff = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF
    window = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_SAFETY_WINDOW

    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::ReleasePublisher.active_mode(at: cutoff - window)
    end

    assert_includes error.message, "cutoff safety window"
    assert_equal :user, SequelAceRelease::ReleasePublisher.active_mode(at: cutoff - window - 1)
    assert_equal :app, SequelAceRelease::ReleasePublisher.active_mode(at: cutoff)
  end

  def test_binds_each_publisher_to_the_release_creation_epoch
    cutoff = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF

    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.5.0-20110",
      login: "Jason-Morcos",
      created_at: cutoff.iso8601
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.5.0-20110",
      login: "sequel-ace-release-automation[bot]",
      created_at: (cutoff - 1).iso8601
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.5.0-20110",
      login: "Jason-Morcos",
      created_at: "not-a-timestamp"
    )
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "production/5.5.0-20110",
      login: "Jason-Morcos",
      created_at: "2026-08-13T00:00:00"
    )
  end

  def test_requires_an_explicit_timezone_in_string_timestamps
    assert_equal Time.utc(2026, 8, 13),
                 SequelAceRelease::ReleasePublisher.publication_time("2026-08-13T02:00:00+02:00")
    assert_equal Time.utc(2026, 8, 13),
                 SequelAceRelease::ReleasePublisher.publication_time("2026-08-13T00:00:00Z")

    ["2026-08-13T00:00:00", "", "not-a-timestamp"].each do |timestamp|
      assert_raises(ArgumentError) do
        SequelAceRelease::ReleasePublisher.publication_time(timestamp)
      end
    end
  end

  def test_rejects_malformed_tags_and_pre_bridge_builds
    refute SequelAceRelease::ReleasePublisher.authorized?(tag: "5.4.0", login: "Jason-Morcos")
    refute SequelAceRelease::ReleasePublisher.authorized?(
      tag: "beta/5.4.0-20105",
      login: "sequel-ace-release-automation[bot]"
    )
  end

  def test_validation_fails_closed
    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::ReleasePublisher.validate!(
        tag: "production/5.4.0-20109",
        login: "another-maintainer",
        at: Time.utc(2026, 8, 13)
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
