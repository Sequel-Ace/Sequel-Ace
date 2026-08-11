# frozen_string_literal: true

require "test_helper"

class ReleaseNamingTest < Minitest::Test
  def test_production_names
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_105, iteration: 2
    )

    assert_equal "production/5.3.2-20105", naming.tag
    assert_equal "5.3.2 (20105) - Release Candidate 2", naming.title
    assert_equal "5.3.2 (20105)", naming.final_title
    assert_equal "prepare-release/5.3.2-20105-2", naming.branch
    assert_equal ["Sequel-Ace-5.3.2.zip"], naming.public_artifacts
    assert_equal "production-5.3.2-20105", naming.ghcr_tag
  end

  def test_beta_names_include_distinct_alpha_artifact
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "beta", version: "5.4.0", build: 20_110, iteration: 3
    )

    assert_equal "beta/5.4.0-20110", naming.tag
    assert_equal "5.4.0 (20110) Beta 3", naming.title
    assert_equal [
      "Sequel-Ace-5.4.0-beta3.zip",
      "Sequel-Ace-5.4.0-beta3-alpha.zip"
    ], naming.public_artifacts
  end

  def test_rejects_invalid_values
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::ReleaseNaming.new(channel: "alpha", version: "5.3.2", build: 1)
    end
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::ReleaseNaming.new(channel: "production", version: "5.3", build: 1)
    end
  end
end
