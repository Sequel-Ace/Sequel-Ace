# frozen_string_literal: true

require "test_helper"

class CliBuildReconciliationTest < Minitest::Test
  def test_canonical_tag_baseline_includes_production_and_beta_tags
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    tags = [
      "production/5.3.1-20104",
      "beta/5.3.2-20106",
      "unrelated/5.3.2-99999"
    ]

    assert_equal 20_106, cli.send(:highest_build_from_tags, tags)
  end

  def test_reconcile_build_refuses_a_number_already_claimed_by_a_beta_tag
    git = Object.new
    git.define_singleton_method(:tags) do |pattern|
      pattern == "beta/*" ? ["beta/5.3.2-20106"] : []
    end
    git.define_singleton_method(:latest_commit_changing_all) { |_paths| nil }
    output = StringIO.new
    error = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: error, env: {})

    status = SequelAceRelease::GitRepository.stub(:new, git) do
      cli.run([
        "reconcile-build",
        "--source-build", "20105",
        "--highest-asc-build", "20104",
        "--cloud-next-build", "20106"
      ])
    end

    assert_equal 1, status
    assert_includes error.string, "canonical release tag build 20106 is ahead of source build 20105"
  end
end
