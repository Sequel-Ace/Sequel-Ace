# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "test_helper"

class ReleaseArtifactWakeStateTest < Minitest::Test
  PRODUCTION_TAG = "production/5.4.0-20109"

  def test_arm_sets_and_reads_back_the_exact_tag
    with_fake_github("none") do |run, state|
      _stdout, stderr, status = run.call("arm", PRODUCTION_TAG)

      assert_predicate status, :success?, stderr
      assert_equal PRODUCTION_TAG, File.read(state).strip
    end
  end

  def test_arm_refuses_to_replace_another_handoff
    with_fake_github("beta/5.5.0-20110") do |run, state|
      _stdout, stderr, status = run.call("arm", PRODUCTION_TAG)

      refute_predicate status, :success?
      assert_includes stderr, "refusing to replace it"
      assert_equal "beta/5.5.0-20110", File.read(state).strip
    end
  end

  def test_clear_is_compare_and_set
    with_fake_github(PRODUCTION_TAG) do |run, state|
      _stdout, stderr, status = run.call("clear", PRODUCTION_TAG)

      assert_predicate status, :success?, stderr
      assert_equal "none", File.read(state).strip
    end
  end

  def test_clear_preserves_a_newer_handoff
    newer_tag = "production/5.4.1-20110"
    with_fake_github(newer_tag) do |run, state|
      stdout, stderr, status = run.call("clear", PRODUCTION_TAG)

      assert_predicate status, :success?, stderr
      assert_includes stdout, "leaving it unchanged"
      assert_equal newer_tag, File.read(state).strip
    end
  end

  def test_malformed_tag_fails_before_api_access
    with_fake_github("none") do |run, state|
      _stdout, stderr, status = run.call("arm", "production/not-a-tag")

      assert_equal 64, status.exitstatus
      assert_includes stderr, "Malformed release artifact wake tag"
      assert_equal "none", File.read(state).strip
    end
  end

  private

  def repo_path(relative_path)
    File.expand_path("../..", __dir__) + "/#{relative_path}"
  end

  def with_fake_github(initial_value)
    Dir.mktmpdir("sequel-ace-wake-state-test") do |directory|
      bin_directory = File.join(directory, "bin")
      state_path = File.join(directory, "state")
      FileUtils.mkdir_p(bin_directory)
      File.write(state_path, "#{initial_value}\n")
      gh_path = File.join(bin_directory, "gh")
      File.write(gh_path, <<~'SH')
        #!/bin/bash
        set -euo pipefail
        if [[ " $* " == *" --method PATCH "* ]]; then
          for argument in "$@"; do
            if [[ "${argument}" == value=* ]]; then
              printf '%s\n' "${argument#value=}" > "${FAKE_GH_STATE}"
              exit 0
            fi
          done
          echo "PATCH omitted value" >&2
          exit 1
        fi
        cat "${FAKE_GH_STATE}"
      SH
      FileUtils.chmod(0o755, gh_path)

      runner = lambda do |operation, tag|
        environment = {
          "FAKE_GH_STATE" => state_path,
          "GH_TOKEN" => "test-token",
          "GITHUB_REPOSITORY" => "Sequel-Ace/Sequel-Ace",
          "PATH" => "#{bin_directory}:#{ENV.fetch('PATH')}"
        }
        Open3.capture3(environment, repo_path("Scripts/release-artifact-wake-state.sh"), operation, tag)
      end
      yield runner, state_path
    end
  end
end
