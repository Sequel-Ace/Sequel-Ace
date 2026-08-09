# frozen_string_literal: true

require "test_helper"

class GitHubClientTest < Minitest::Test
  def test_lists_releases_with_explicit_pagination_query
    transport = FakeTransport.new([
      http_response(body: [{ "tag_name" => "production/5.3.1-20104" }])
    ])
    releases = SequelAceRelease::GitHubClient.new(token: "token", transport: transport).releases

    assert_equal "production/5.3.1-20104", releases.first.fetch("tag_name")
    assert_equal({ "per_page" => 100 }, transport.requests.first[:query])
  end

  def test_release_pagination_follows_the_recorded_next_link
    transport = FakeTransport.new([
      http_response(
        body: fixture_json("github/releases-page-1.json"),
        headers: { "link" => '<https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases?page=2>; rel="next"' }
      ),
      http_response(body: fixture_json("github/releases-page-2.json"))
    ])
    releases = SequelAceRelease::GitHubClient.new(token: "token", transport: transport).releases

    assert_equal ["production/5.3.0-20103", "production/5.3.1-20104"], releases.map { |release| release.fetch("tag_name") }
    assert_includes transport.requests.last[:path], "page=2"
    assert_nil transport.requests.last[:query]
  end

  def test_reads_the_exact_main_ref_sha
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => "a" * 40 } })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    assert_equal "a" * 40, client.ref_sha
    assert_equal "/repos/Sequel-Ace/Sequel-Ace/git/ref/heads/main", transport.requests.first[:path]
  end

  def test_accepts_an_exact_release_target_that_remains_an_unchanged_main_ancestor
    target_sha = "a" * 40
    current_main = "b" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => current_main } }),
      http_response(body: {
        "status" => "ahead",
        "ahead_by" => 2,
        "behind_by" => 0,
        "merge_base_commit" => { "sha" => target_sha },
        "files" => [{ "filename" => "README.md" }]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    result = client.validate_release_target!(
      target_sha: target_sha,
      protected_paths: ["CHANGELOG.md", "Info.plist"]
    )

    assert_equal current_main, result.fetch("current_main_sha")
    assert_equal 2, result.fetch("main_commits_after_target")
    assert_equal "/repos/Sequel-Ace/Sequel-Ace/compare/#{target_sha}...#{current_main}", transport.requests.last[:path]
  end

  def test_rejects_a_release_target_if_a_protected_file_changed_after_it
    target_sha = "a" * 40
    current_main = "b" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => current_main } }),
      http_response(body: {
        "status" => "ahead",
        "ahead_by" => 1,
        "behind_by" => 0,
        "merge_base_commit" => { "sha" => target_sha },
        "files" => [{ "filename" => "CHANGELOG.md" }]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.validate_release_target!(target_sha: target_sha, protected_paths: ["CHANGELOG.md"])
    end
    assert_includes error.message, "CHANGELOG.md"
  end

  def test_rejects_a_release_target_if_a_protected_file_was_renamed_after_it
    target_sha = "a" * 40
    current_main = "b" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => current_main } }),
      http_response(body: {
        "status" => "ahead",
        "ahead_by" => 1,
        "behind_by" => 0,
        "merge_base_commit" => { "sha" => target_sha },
        "files" => [{ "filename" => "OLD_CHANGELOG.md", "previous_filename" => "CHANGELOG.md" }]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.validate_release_target!(target_sha: target_sha, protected_paths: ["CHANGELOG.md"])
    end
    assert_includes error.message, "CHANGELOG.md"
  end

  def test_rejects_a_release_target_that_is_not_on_current_main
    target_sha = "a" * 40
    current_main = "b" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => current_main } }),
      http_response(body: {
        "status" => "diverged",
        "ahead_by" => 1,
        "behind_by" => 1,
        "merge_base_commit" => { "sha" => "c" * 40 },
        "files" => []
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.validate_release_target!(target_sha: target_sha, protected_paths: ["CHANGELOG.md"])
    end
    assert_includes error.message, "no longer an ancestor"
  end

  def test_rejects_a_truncated_release_target_comparison
    target_sha = "a" * 40
    current_main = "b" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => current_main } }),
      http_response(body: {
        "status" => "ahead",
        "ahead_by" => 1,
        "behind_by" => 0,
        "merge_base_commit" => { "sha" => target_sha },
        "files" => Array.new(300) { |index| { "filename" => "file-#{index}" } }
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.validate_release_target!(target_sha: target_sha, protected_paths: ["CHANGELOG.md"])
    end
    assert_includes error.message, "too large"
  end

  def test_rejects_release_target_ancestry_without_file_evidence
    target_sha = "a" * 40
    current_main = "b" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => current_main } }),
      http_response(body: {
        "status" => "ahead",
        "ahead_by" => 1,
        "behind_by" => 0,
        "merge_base_commit" => { "sha" => target_sha }
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.validate_release_target!(target_sha: target_sha, protected_paths: ["CHANGELOG.md"])
    end
    assert_includes error.message, "file evidence"
  end

  def test_creates_only_a_github_signed_bot_commit_without_identity_overrides
    created_sha = "c" * 40
    responses = [
      http_response(status: 201, body: { "ref" => "refs/heads/prepare-release/5.3.2-20105-rc1" }),
      http_response(body: {
        "data" => {
          "createCommitOnBranch" => {
            "commit" => {
              "oid" => created_sha,
              "url" => "https://github.com/Sequel-Ace/Sequel-Ace/commit/#{created_sha}",
              "signature" => {
                "isValid" => true,
                "state" => "VALID",
                "wasSignedByGitHub" => true
              }
            }
          }
        }
      })
    ]
    transport = FakeTransport.new(responses)
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    Dir.mktmpdir do |directory|
      file = File.join(directory, "CHANGELOG.md")
      File.write(file, "release notes")
      commit = client.create_bot_commit(
        base_sha: "a" * 40,
        branch: "prepare-release/5.3.2-20105-rc1",
        message: "Prepare release #changed",
        repository_root: directory,
        changed_paths: [{ "status" => " M", "path" => "CHANGELOG.md" }]
      )
      assert_equal created_sha, commit.fetch("sha")
      assert_equal true, commit.dig("verification", "was_signed_by_github")
    end

    ref_request, commit_request = transport.requests
    assert_equal "/repos/Sequel-Ace/Sequel-Ace/git/refs", ref_request[:path]
    assert_equal "a" * 40, ref_request.dig(:body, "sha")
    assert_equal "/graphql", commit_request[:path]
    input = commit_request.dig(:body, "variables", "input")
    assert_equal "a" * 40, input.fetch("expectedHeadOid")
    assert_equal "prepare-release/5.3.2-20105-rc1", input.dig("branch", "branchName")
    assert_equal "release notes", Base64.strict_decode64(input.dig("fileChanges", "additions", 0, "contents"))
    refute input.key?("author")
    refute input.key?("committer")
    refute input.key?("signature")
    refute transport.requests.any? { |request| request[:path].end_with?("/git/commits") }
  end

  def test_reconciles_a_github_accepted_commit_when_the_mutation_response_is_lost
    base_sha = "a" * 40
    created_sha = "c" * 40
    contents = "release notes"
    transport = FakeTransport.new([
      http_response(status: 201, body: { "ref" => "refs/heads/prepare-release/5.3.2-20105-rc1" }),
      http_response(status: 502, body: { "message" => "upstream response lost" }),
      http_response(body: { "object" => { "sha" => created_sha } }),
      inspected_commit_response(sha: created_sha, parent: base_sha),
      comparison_response(base_sha: base_sha, head_sha: created_sha, contents: contents)
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "CHANGELOG.md"), contents)
      commit = client.create_bot_commit(
        base_sha: base_sha,
        branch: "prepare-release/5.3.2-20105-rc1",
        message: "Prepare release #changed",
        repository_root: directory,
        changed_paths: [{ "status" => " M", "path" => "CHANGELOG.md" }]
      )

      assert_equal created_sha, commit.fetch("sha")
      assert_equal true, commit.fetch("reconciled")
      assert_equal true, commit.dig("verification", "was_signed_by_github")
    end
    assert_equal ["POST", "POST", "GET", "POST", "GET"], transport.requests.map { |request| request.fetch(:method) }
  end

  def test_unverified_bot_commit_is_rejected_after_github_creates_the_branch
    created_sha = "c" * 40
    responses = [
      http_response(status: 201, body: { "ref" => "refs/heads/prepare-release/5.3.2-20105-rc1" }),
      http_response(body: {
        "data" => {
          "createCommitOnBranch" => {
            "commit" => {
              "oid" => created_sha,
              "url" => "https://github.com/Sequel-Ace/Sequel-Ace/commit/#{created_sha}",
              "signature" => {
                "isValid" => false,
                "state" => "UNSIGNED",
                "wasSignedByGitHub" => false
              }
            }
          }
        }
      }),
      http_response(body: { "object" => { "sha" => created_sha } }),
      http_response(body: {
        "data" => {
          "repository" => {
            "object" => {
              "oid" => created_sha,
              "url" => "https://github.com/Sequel-Ace/Sequel-Ace/commit/#{created_sha}",
              "parents" => { "nodes" => [{ "oid" => "a" * 40 }] },
              "signature" => {
                "isValid" => false,
                "state" => "UNSIGNED",
                "wasSignedByGitHub" => false
              }
            }
          }
        }
      })
    ]
    transport = FakeTransport.new(responses)
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "CHANGELOG.md"), "release notes")
      assert_raises(SequelAceRelease::ValidationError) do
        client.create_bot_commit(
          base_sha: "a" * 40,
          branch: "prepare-release/5.3.2-20105-rc1",
          message: "Prepare release #changed",
          repository_root: directory,
          changed_paths: [{ "status" => " M", "path" => "CHANGELOG.md" }]
        )
      end
    end
    assert_equal [
      "/repos/Sequel-Ace/Sequel-Ace/git/refs",
      "/graphql",
      "/repos/Sequel-Ace/Sequel-Ace/git/ref/heads/prepare-release/5.3.2-20105-rc1",
      "/graphql"
    ], transport.requests.map { |request| request[:path] }
    refute transport.requests.any? { |request| request[:path].end_with?("/git/commits") }
  end

  def test_unauthorized_preparation_path_aborts
    client = SequelAceRelease::GitHubClient.new(
      token: "token",
      transport: FakeTransport.new([http_response(body: { "tree" => { "sha" => "base-tree" } })])
    )
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "Source.swift"), "unexpected")
      error = assert_raises(SequelAceRelease::ValidationError) do
        client.create_bot_commit(
          base_sha: "a" * 40,
          branch: "prepare-release/5.3.2-20105-rc1",
          message: "Prepare",
          repository_root: directory,
          changed_paths: [{ "status" => "??", "path" => "Source.swift" }]
        )
      end
      assert_includes error.message, "unauthorized path"
    end
  end

  def test_cleans_up_only_the_exact_failed_release_branch_and_pull_request
    expected_sha = "c" * 40
    branch = "prepare-release/5.3.2-20105-1"
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => expected_sha } }),
      http_response(body: [{
        "number" => 123,
        "head" => { "ref" => branch, "sha" => expected_sha }
      }]),
      http_response(body: { "number" => 123, "state" => "closed" }),
      http_response(body: { "object" => { "sha" => expected_sha } }),
      http_response(status: 204, body: nil)
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    result = client.cleanup_release_branch(branch: branch, expected_sha: expected_sha)

    assert_equal true, result.fetch("deleted")
    assert_equal [123], result.fetch("closed_pull_requests")
    pull_query = transport.requests[1]
    assert_equal "GET", pull_query.fetch(:method)
    assert_equal "Sequel-Ace:#{branch}", pull_query.dig(:query, "head")
    assert_equal "closed", transport.requests[2].dig(:body, "state")
    assert_equal "DELETE", transport.requests.last.fetch(:method)
  end

  def test_cleanup_reconciles_an_unpersisted_generated_commit_by_parent_and_content
    base_sha = "a" * 40
    created_sha = "c" * 40
    branch = "prepare-release/5.3.2-20105-1"
    contents = "release notes"
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => created_sha } }),
      http_response(body: { "object" => { "sha" => created_sha } }),
      inspected_commit_response(sha: created_sha, parent: base_sha, signed: false),
      comparison_response(base_sha: base_sha, head_sha: created_sha, contents: contents),
      http_response(body: []),
      http_response(body: { "object" => { "sha" => created_sha } }),
      http_response(status: 204, body: nil)
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "CHANGELOG.md"), contents)
      result = client.cleanup_release_branch(
        branch: branch,
        expected_sha: base_sha,
        base_sha: base_sha,
        repository_root: directory,
        changed_paths: [{ "status" => " M", "path" => "CHANGELOG.md" }]
      )

      assert_equal true, result.fetch("deleted")
      assert_equal true, result.fetch("reconciled_generated_commit")
      assert_equal created_sha, result.fetch("sha")
      assert_equal false, result.dig("commit_verification", "verified")
    end
    assert_equal "DELETE", transport.requests.last.fetch(:method)
  end

  def test_cleanup_rejects_a_generated_commit_with_different_content
    base_sha = "a" * 40
    created_sha = "c" * 40
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => created_sha } }),
      http_response(body: { "object" => { "sha" => created_sha } }),
      inspected_commit_response(sha: created_sha, parent: base_sha),
      comparison_response(base_sha: base_sha, head_sha: created_sha, contents: "different contents")
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "CHANGELOG.md"), "approved contents")
      error = assert_raises(SequelAceRelease::ValidationError) do
        client.cleanup_release_branch(
          branch: "prepare-release/5.3.2-20105-1",
          expected_sha: base_sha,
          base_sha: base_sha,
          repository_root: directory,
          changed_paths: [{ "status" => " M", "path" => "CHANGELOG.md" }]
        )
      end
      assert_includes error.message, "content does not match"
    end
    refute transport.requests.any? { |request| request.fetch(:method) == "DELETE" }
  end

  def test_release_branch_cleanup_rejects_a_changed_head_without_mutation
    transport = FakeTransport.new([
      http_response(body: { "object" => { "sha" => "d" * 40 } })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.cleanup_release_branch(
        branch: "prepare-release/5.3.2-20105-1",
        expected_sha: "c" * 40
      )
    end

    assert_includes error.message, "head changed"
    assert_equal ["GET"], transport.requests.map { |request| request.fetch(:method) }
  end

  def test_release_branch_cleanup_is_idempotent_when_the_branch_is_absent
    transport = FakeTransport.new([
      http_response(status: 404, body: { "message" => "Not Found" })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    result = client.cleanup_release_branch(
      branch: "prepare-release/5.3.2-20105-1",
      expected_sha: "c" * 40
    )

    assert_equal false, result.fetch("deleted")
    assert_equal "already_absent", result.fetch("reason")
  end

  def test_only_labels_an_author_new_when_their_first_merged_pr_is_in_this_release
    transport = FakeTransport.new([
      http_response(body: { "number" => 2500, "user" => { "login" => "new-person" } }),
      http_response(body: { "number" => 2501, "user" => { "login" => "established-person" } }),
      http_response(body: { "items" => [{ "number" => 2500 }] }),
      http_response(body: { "items" => [{ "number" => 1000 }] })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    assert_equal({ 2500 => "new-person" }, client.new_contributors([2500, 2501]))
    search = transport.requests.select { |request| request[:path] == "/search/issues" }
    assert_equal "created", search.first.dig(:query, "sort")
    assert_includes search.first.dig(:query, "q"), "is:merged"
  end

  def test_wait_for_checks_uses_the_latest_rerun_for_each_name
    transport = FakeTransport.new([
      http_response(body: {
        "check_runs" => [
          { "id" => 1, "name" => "Run Tests", "started_at" => "2026-08-08T10:00:00Z", "conclusion" => "failure" },
          { "id" => 2, "name" => "Run Tests", "started_at" => "2026-08-08T11:00:00Z", "conclusion" => "success" }
        ]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    assert_equal 2, client.wait_for_checks(
      commit_sha: "a" * 40,
      required_names: ["Run Tests"],
      timeout_seconds: 0,
      interval_seconds: 0
    ).length
  end

  def test_wait_for_checks_does_not_accept_an_old_success_while_a_rerun_is_pending
    transport = FakeTransport.new([
      http_response(body: {
        "check_runs" => [
          { "id" => 1, "name" => "Run Tests", "started_at" => "2026-08-08T10:00:00Z", "conclusion" => "success" },
          { "id" => 2, "name" => "Run Tests", "started_at" => "2026-08-08T11:00:00Z", "conclusion" => nil }
        ]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.wait_for_checks(
        commit_sha: "a" * 40,
        required_names: ["Run Tests"],
        timeout_seconds: 0,
        interval_seconds: 0
      )
    end
    assert_includes error.message, "timed out"
  end

  def test_wait_for_checks_rejects_any_failed_exact_head_check_when_required
    transport = FakeTransport.new([
      http_response(body: {
        "check_runs" => [
          { "id" => 1, "name" => "Run Tests", "conclusion" => "success" },
          { "id" => 2, "name" => "Unexpected Required Gate", "conclusion" => "failure" }
        ]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    error = assert_raises(SequelAceRelease::ValidationError) do
      client.wait_for_checks(
        commit_sha: "a" * 40,
        required_names: ["Run Tests"],
        timeout_seconds: 0,
        interval_seconds: 0,
        require_all: true
      )
    end
    assert_includes error.message, "Unexpected Required Gate"
  end

  def test_required_checks_must_be_success_not_skipped
    transport = FakeTransport.new([
      http_response(body: {
        "check_runs" => [{ "id" => 1, "name" => "Run Tests", "conclusion" => "skipped" }]
      })
    ])
    client = SequelAceRelease::GitHubClient.new(token: "token", transport: transport)

    assert_raises(SequelAceRelease::ValidationError) do
      client.wait_for_checks(
        commit_sha: "a" * 40,
        required_names: ["Run Tests"],
        timeout_seconds: 0,
        interval_seconds: 0
      )
    end
  end

  def test_asset_upload_is_idempotent_only_for_the_same_checksum
    Dir.mktmpdir do |directory|
      path = File.join(directory, "Sequel-Ace-5.3.2.zip")
      File.binwrite(path, "verified zip bytes")
      digest = Digest::SHA256.file(path).hexdigest
      client = SequelAceRelease::GitHubClient.new(token: "token", transport: FakeTransport.new([]))
      release = {
        "id" => 100,
        "assets" => [{ "id" => 200, "name" => File.basename(path), "digest" => "sha256:#{digest}" }]
      }

      assert_equal 200, client.upload_release_asset(release: release, path: path).fetch("id")
      release["assets"].first["digest"] = "sha256:#{'0' * 64}"
      assert_raises(SequelAceRelease::ValidationError) do
        client.upload_release_asset(release: release, path: path)
      end
    end
  end

  private

  def inspected_commit_response(sha:, parent:, signed: true)
    http_response(body: {
      "data" => {
        "repository" => {
          "object" => {
            "oid" => sha,
            "url" => "https://github.com/Sequel-Ace/Sequel-Ace/commit/#{sha}",
            "parents" => { "nodes" => [{ "oid" => parent }] },
            "signature" => {
              "isValid" => signed,
              "state" => signed ? "VALID" : "UNSIGNED",
              "wasSignedByGitHub" => signed
            }
          }
        }
      }
    })
  end

  def comparison_response(base_sha:, head_sha:, contents:)
    http_response(body: {
      "status" => "ahead",
      "ahead_by" => 1,
      "behind_by" => 0,
      "total_commits" => 1,
      "merge_base_commit" => { "sha" => base_sha },
      "commits" => [{ "sha" => head_sha }],
      "files" => [{
        "filename" => "CHANGELOG.md",
        "status" => "modified",
        "sha" => Digest::SHA1.hexdigest("blob #{contents.bytesize}\0".b + contents.b)
      }]
    })
  end
end
