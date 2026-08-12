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

  def test_arm_atomically_replaces_the_exact_predecessor_for_a_forward_recovery
    recovery_tag = "production/5.4.0-20111"
    with_fake_github(PRODUCTION_TAG) do |run, state|
      stdout, stderr, status = run.call("arm", recovery_tag, PRODUCTION_TAG)

      assert_predicate status, :success?, stderr
      assert_includes stdout, "Atomically forwarding artifact wake state"
      assert_equal recovery_tag, File.read(state).strip
    end
  end

  def test_forward_replacement_requires_the_live_exact_predecessor
    recovery_tag = "production/5.4.0-20111"
    with_fake_github("production/5.4.0-20110") do |run, state|
      _stdout, stderr, status = run.call("arm", recovery_tag, PRODUCTION_TAG)

      refute_predicate status, :success?
      assert_includes stderr, "refusing to replace it"
      assert_equal "production/5.4.0-20110", File.read(state).strip
    end
  end

  def test_forward_replacement_cannot_change_release_identity_or_move_backward
    with_fake_github(PRODUCTION_TAG) do |run, state|
      [
        "beta/5.4.0-20111",
        "production/5.4.1-20111",
        "production/5.4.0-20108"
      ].each do |candidate|
        _stdout, _stderr, status = run.call("arm", candidate, PRODUCTION_TAG)

        refute_predicate status, :success?, candidate
        assert_equal PRODUCTION_TAG, File.read(state).strip
      end
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

  def test_workflow_credentials_mint_and_revoke_an_exact_repository_variables_token
    with_fake_github("none", provided_token: false) do |run, state, log|
      _stdout, stderr, status = run.call("arm", PRODUCTION_TAG)

      assert_predicate status, :success?, stderr
      assert_equal PRODUCTION_TAG, File.read(state).strip
      api_log = File.read(log)
      assert_includes api_log, "repos/Sequel-Ace/Sequel-Ace/installation"
      assert_includes api_log, "app/installations/123/access_tokens"
      assert_includes api_log, '"repository_ids":[12345]'
      assert_includes api_log, '"actions_variables":"write"'
      assert_includes api_log, "--method DELETE installation/token"
    end
  end

  private

  def repo_path(relative_path)
    File.expand_path("../..", __dir__) + "/#{relative_path}"
  end

  def with_fake_github(initial_value, provided_token: true)
    Dir.mktmpdir("sequel-ace-wake-state-test") do |directory|
      bin_directory = File.join(directory, "bin")
      state_path = File.join(directory, "state")
      log_path = File.join(directory, "api-log")
      FileUtils.mkdir_p(bin_directory)
      File.write(state_path, "#{initial_value}\n")
      File.write(log_path, "")
      gh_path = File.join(bin_directory, "gh")
      File.write(gh_path, <<~'SH')
        #!/bin/bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${FAKE_GH_LOG}"
        if [[ " $* " == *" app/installations/123/access_tokens "* ]]; then
          payload="$(cat)"
          printf '%s\n' "${payload}" >> "${FAKE_GH_LOG}"
          printf '%s\n' '{"token":"generated-test-token","permissions":{"actions_variables":"write","metadata":"read"},"repositories":[{"id":12345}]}'
          exit 0
        fi
        if [[ " $* " == *" --method DELETE installation/token "* ]]; then
          exit 0
        fi
        if [[ " $* " == *" repos/Sequel-Ace/Sequel-Ace/installation "* ]]; then
          printf '%s\n' '{"id":123}'
          exit 0
        fi
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
      openssl_path = File.join(bin_directory, "openssl")
      File.write(openssl_path, <<~'SH')
        #!/bin/bash
        set -euo pipefail
        cat >/dev/null
        printf 'encoded'
      SH
      FileUtils.chmod(0o755, openssl_path)

      runner = lambda do |operation, tag, predecessor = nil|
        environment = {
          "FAKE_GH_STATE" => state_path,
          "FAKE_GH_LOG" => log_path,
          "GITHUB_REPOSITORY" => "Sequel-Ace/Sequel-Ace",
          "PATH" => "#{bin_directory}:#{ENV.fetch('PATH')}"
        }
        if provided_token
          environment["GH_TOKEN"] = "test-token"
        else
          environment.merge!(
            "GITHUB_REPOSITORY_ID" => "12345",
            "SA_RELEASE_GITHUB_APP_CLIENT_ID" => "Iv1.test-client",
            "SA_RELEASE_GITHUB_APP_PRIVATE_KEY" => "test-private-key"
          )
        end
        arguments = [repo_path("Scripts/release-artifact-wake-state.sh"), operation, tag]
        arguments << predecessor if predecessor
        Open3.capture3(environment, *arguments)
      end
      yield runner, state_path, log_path
    end
  end
end
