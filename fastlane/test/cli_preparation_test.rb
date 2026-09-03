# frozen_string_literal: true

require "test_helper"

class CLIPreparationTest < Minitest::Test
  def test_accepts_changelog_only_when_the_release_version_is_already_prepared
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    files = Minitest::Mock.new
    files.expect :current, { "version" => "6.0.0", "build" => 20_111 }
    files.expect :release_tag, "beta/6.0.0-20111"

    SequelAceRelease::VersionFiles.stub(:new, files) do
      cli.send(
        :validate_preparation_paths!,
        [{ "status" => " M", "path" => "CHANGELOG.md" }],
        version: "6.0.0",
        build: 20_111,
        channel: "beta"
      )
    end

    files.verify
  end

  def test_rejects_changelog_only_when_the_release_version_is_not_prepared
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    files = Minitest::Mock.new
    files.expect :current, { "version" => "6.0.0", "build" => 20_111 }
    files.expect :release_tag, "beta/6.0.0-20110"

    SequelAceRelease::VersionFiles.stub(:new, files) do
      error = assert_raises(SequelAceRelease::ValidationError) do
        cli.send(
          :validate_preparation_paths!,
          [{ "status" => " M", "path" => "CHANGELOG.md" }],
          version: "6.0.0",
          build: 20_111,
          channel: "beta"
        )
      end
      assert_includes error.message, "did not converge"
    end

    files.verify
  end
end
