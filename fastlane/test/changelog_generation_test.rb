# frozen_string_literal: true

require "test_helper"
require "open3"

class ChangelogGenerationTest < Minitest::Test
  def test_repeated_beta_regeneration_keeps_the_complete_version_range
    with_gnu_compatible_mktemp do |environment|
      Dir.mktmpdir do |directory|
        git(directory, "init", "--initial-branch=main")
        git(directory, "config", "user.name", "Release Test")
        git(directory, "config", "user.email", "release@example.invalid")
        changelog = File.join(directory, "CHANGELOG.md")
        File.write(changelog, "# Changelog\n\n## [5.3.1](https://example.invalid/5.3.1)\n\nStable.\n")
        commit_all(directory, "Initial stable release")
        git(directory, "tag", "production/5.3.1-20104")

        File.write(File.join(directory, "first-beta.txt"), "first\n")
        commit_all(directory, "Fix first beta behavior #fixed")
        generate_changelog(directory, changelog, environment)
        commit_all(directory, "Prepare 5.4.0 (20105) release #changed")
        git(directory, "tag", "beta/5.4.0-20105")

        File.write(File.join(directory, "second-beta.txt"), "second\n")
        commit_all(directory, "Fix second beta behavior #fixed")
        generate_changelog(directory, changelog, environment)

        content = File.read(changelog)
        assert_equal 1, content.scan("Fix first beta behavior").length
        assert_equal 1, content.scan("Fix second beta behavior").length
        refute_includes content, "Prepare 5.4.0 (20105) release"
      end
    end
  end

  private

  def generate_changelog(directory, changelog, environment = {})
    script = File.expand_path("../../Scripts/generate-changelog.sh", __dir__)
    _stdout, stderr, status = Open3.capture3(
      {
        "CHANGELOG_FILE" => changelog,
        "RANGE_START" => "production/5.3.1-20104",
        "RANGE_END" => "HEAD"
      }.merge(environment),
      script,
      "5.4.0",
      chdir: directory
    )
    raise "changelog generation failed: #{stderr}" unless status.success?
  end

  def commit_all(directory, message)
    git(directory, "add", ".")
    git(directory, "-c", "commit.gpgsign=false", "commit", "-m", message)
  end

  def git(directory, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", directory, *arguments)
    raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

    stdout.strip
  end

  def with_gnu_compatible_mktemp
    Dir.mktmpdir do |binary_directory|
      fake_mktemp = File.join(binary_directory, "mktemp")
      File.write(fake_mktemp, <<~'BASH')
        #!/usr/bin/env bash
        set -euo pipefail

        if [[ "${1:-}" == "-t" ]]; then
          echo "GNU-style mktemp requires an XXXXXX template" >&2
          exit 64
        fi
        [[ "${1:-}" == *XXXXXX* ]] || {
          echo "mktemp template must contain XXXXXX" >&2
          exit 64
        }
        exec /usr/bin/mktemp "$@"
      BASH
      FileUtils.chmod(0o755, fake_mktemp)

      yield("PATH" => "#{binary_directory}:#{ENV.fetch('PATH')}")
    end
  end
end
