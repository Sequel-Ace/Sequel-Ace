# frozen_string_literal: true

require "base64"
require "digest"
require "uri"

module SequelAceRelease
  class GitHubClient
    API_URL = "https://api.github.com/"
    UPLOAD_URL = "https://uploads.github.com/"
    CREATE_COMMIT_MUTATION = <<~GRAPHQL.freeze
      mutation CreateReleaseCommit($input: CreateCommitOnBranchInput!) {
        createCommitOnBranch(input: $input) {
          commit {
            oid
            url
            signature {
              isValid
              state
              wasSignedByGitHub
            }
          }
        }
      }
    GRAPHQL
    INSPECT_COMMIT_QUERY = <<~GRAPHQL.freeze
      query InspectReleaseCommit($owner: String!, $name: String!, $oid: GitObjectID!) {
        repository(owner: $owner, name: $name) {
          object(oid: $oid) {
            ... on Commit {
              oid
              url
              parents(first: 2) {
                nodes {
                  oid
                }
              }
              signature {
                isValid
                state
                wasSignedByGitHub
              }
            }
          }
        }
      }
    GRAPHQL

    def initialize(token:, repository: Config::REPOSITORY, transport: nil)
      raise ValidationError, "GitHub token is required" if token.to_s.empty?

      @token = token
      @repository = repository
      @transport = transport || HTTPTransport.new(
        base_url: API_URL,
        default_headers: {
          "Accept" => "application/vnd.github+json",
          "Authorization" => "Bearer #{token}",
          "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent" => "sequel-ace-release-tool"
        }
      )
    end

    def releases
      paginate("/repos/#{@repository}/releases", { "per_page" => 100 })
    end

    def latest_stable_release
      releases
        .select { |release| !release["draft"] && !release["prerelease"] && release["tag_name"].to_s.start_with?("production/") }
        .max_by { |release| release["published_at"].to_s }
    end

    def release_by_tag(tag)
      request!("GET", "/repos/#{@repository}/releases/tags/#{URI.encode_www_form_component(tag)}")
    end

    def pull_request(number)
      request!("GET", "/repos/#{@repository}/pulls/#{Integer(number)}")
    end

    def ref_sha(ref = "heads/main")
      value = request!("GET", "/repos/#{@repository}/git/ref/#{ref}")
      value.fetch("object").fetch("sha")
    end

    def new_contributors(pr_numbers)
      numbers = Array(pr_numbers).map { |number| Integer(number) }.uniq
      by_login = numbers.each_with_object({}) do |number, result|
        login = pull_request(number).dig("user", "login").to_s
        next if login.empty?

        (result[login] ||= []) << number
      end

      by_login.each_with_object({}) do |(login, current_numbers), result|
        next unless login.match?(/\A[A-Za-z0-9-]+\z/)

        response = @transport.request("GET", "/search/issues", query: {
          "q" => "repo:#{@repository} is:pr is:merged author:#{login}",
          "sort" => "created",
          "order" => "asc",
          "per_page" => 1
        })
        first_number = Array(ensure_response!(response, [200]).fetch("items", [])).first&.fetch("number", nil)
        first_number = Integer(first_number) if first_number
        result[first_number] = login if first_number && current_numbers.include?(first_number)
      rescue APIError, ArgumentError, TypeError
        # Contributor enrichment must never turn an unverified identity into a
        # "New Contributor" claim. The complete change list remains intact.
        next
      end
    end

    def create_bot_commit(base_sha:, branch:, message:, repository_root:, changed_paths:)
      raise ValidationError, "release branch must begin with prepare-release/" unless branch.start_with?("prepare-release/")
      raise ValidationError, "release preparation produced no changes" if changed_paths.empty?

      additions = []
      deletions = []
      changed_paths.each do |change|
        path = change.fetch("path")
        validate_release_path!(path)
        if change.fetch("status").include?("D")
          deletions << { "path" => path }
        else
          bytes = File.binread(File.join(repository_root, path))
          additions << { "path" => path, "contents" => Base64.strict_encode64(bytes) }
        end
      end

      begin
        request!("POST", "/repos/#{@repository}/git/refs", body: {
          "ref" => "refs/heads/#{branch}",
          "sha" => base_sha
        })
      rescue APIError => creation_error
        begin
          raise creation_error unless ref_sha("heads/#{branch}") == base_sha
        rescue APIError
          raise creation_error
        end
      end
      file_changes = {}
      file_changes["additions"] = additions unless additions.empty?
      file_changes["deletions"] = deletions unless deletions.empty?
      begin
        data = graphql!(CREATE_COMMIT_MUTATION, {
          "input" => {
            "branch" => {
              "repositoryNameWithOwner" => @repository,
              "branchName" => branch
            },
            "expectedHeadOid" => base_sha,
            "fileChanges" => file_changes,
            "message" => { "headline" => message }
          }
        })
        created = data.fetch("createCommitOnBranch").fetch("commit")
        verified_commit_evidence(created)
      rescue APIError, KeyError, ValidationError => mutation_error
        begin
          inspect_generated_commit!(
            branch: branch,
            base_sha: base_sha,
            repository_root: repository_root,
            changed_paths: changed_paths,
            require_github_signature: true
          )
        rescue Error, KeyError => reconciliation_error
          raise ValidationError,
                "GitHub release commit outcome is ambiguous: #{mutation_error.message}; " \
                "remote reconciliation failed: #{reconciliation_error.message}"
        end
      end
    end

    def create_pull_request(branch:, title:, body:, base: "main")
      request!("POST", "/repos/#{@repository}/pulls", body: {
        "title" => title,
        "head" => branch,
        "base" => base,
        "body" => body,
        "draft" => false
      })
    end

    def wait_for_checks(commit_sha:, required_names:, timeout_seconds: 7_200, interval_seconds: 30, require_all: false, stability_polls: 2)
      deadline = Time.now + timeout_seconds
      required = Array(required_names).map(&:strip).reject(&:empty?).uniq
      raise ValidationError, "at least one required check name is required" if required.empty?
      stable_signature = nil
      stable_count = 0

      loop do
        runs = paginate("/repos/#{@repository}/commits/#{commit_sha}/check-runs", { "per_page" => 100 }, data_key: "check_runs")
        latest_by_name = runs.group_by { |run| run["name"] }.transform_values do |named_runs|
          named_runs.max_by { |run| check_run_order(run) }
        end
        required_failures = required.filter_map do |name|
          conclusion = latest_by_name[name]&.fetch("conclusion", nil)
          name if conclusion && conclusion != "success"
        end
        optional_failures = (require_all ? latest_by_name.keys - required : []).filter_map do |name|
          conclusion = latest_by_name[name]&.fetch("conclusion", nil)
          name if conclusion && !%w[success neutral skipped].include?(conclusion)
        end
        failures = required_failures + optional_failures
        raise ValidationError, "required checks failed: #{failures.join(', ')}" unless failures.empty?

        required_complete = required.all? do |name|
          latest_by_name[name]&.fetch("conclusion", nil) == "success"
        end
        all_complete = latest_by_name.any? && latest_by_name.values.all? do |run|
          %w[success neutral skipped].include?(run&.fetch("conclusion", nil))
        end
        complete = required_complete && (!require_all || all_complete)
        if complete
          signature = latest_by_name.sort.map do |name, run|
            [name, run["id"], run["conclusion"]]
          end
          stable_count = signature == stable_signature ? stable_count + 1 : 1
          stable_signature = signature
          return runs if !require_all || stable_count >= Integer(stability_polls)
        else
          stable_signature = nil
          stable_count = 0
        end
        raise ValidationError, "timed out waiting for required checks: #{required.join(', ')}" if Time.now >= deadline

        sleep(interval_seconds)
      end
    end

    def merge_pull_request(number:, expected_head_sha:)
      response = request!("PUT", "/repos/#{@repository}/pulls/#{Integer(number)}/merge", body: {
        "sha" => expected_head_sha,
        "merge_method" => "merge"
      })
      raise ValidationError, "GitHub declined to merge release PR: #{response['message']}" unless response["merged"] == true

      response
    end

    def delete_branch(branch)
      request!("DELETE", "/repos/#{@repository}/git/refs/heads/#{URI.encode_www_form_component(branch)}", expected: [204])
      true
    end

    def cleanup_release_branch(branch:, expected_sha:, base_sha: nil, repository_root: nil, changed_paths: nil)
      raise ValidationError, "release branch must begin with prepare-release/" unless branch.start_with?("prepare-release/")
      unless expected_sha.to_s.match?(/\A[0-9a-f]{40,64}\z/i)
        raise ValidationError, "expected release branch SHA is malformed"
      end

      begin
        actual_sha = ref_sha("heads/#{branch}")
      rescue APIError => e
        raise unless e.message.include?("HTTP 404")

        return { "branch" => branch, "deleted" => false, "reason" => "already_absent" }
      end
      reconciliation = nil
      cleanup_sha = expected_sha
      unless actual_sha == expected_sha
        unless base_sha && repository_root && changed_paths
          raise ValidationError, "release branch head changed before cleanup (expected #{expected_sha}, found #{actual_sha})"
        end
        reconciliation = inspect_generated_commit!(
          branch: branch,
          base_sha: base_sha,
          repository_root: repository_root,
          changed_paths: changed_paths,
          require_github_signature: false
        )
        cleanup_sha = reconciliation.fetch("sha")
      end

      pulls = open_pull_requests_for_branch(branch)
      mismatched = pulls.reject do |pull|
        pull.dig("head", "ref") == branch && pull.dig("head", "sha") == cleanup_sha
      end
      unless mismatched.empty?
        raise ValidationError, "release branch PR head changed before cleanup"
      end
      pulls.each do |pull|
        request!("PATCH", "/repos/#{@repository}/pulls/#{Integer(pull.fetch('number'))}", body: { "state" => "closed" })
      end

      rechecked_sha = ref_sha("heads/#{branch}")
      unless rechecked_sha == cleanup_sha
        raise ValidationError, "release branch head changed during cleanup (expected #{cleanup_sha}, found #{rechecked_sha})"
      end
      delete_branch(branch)
      {
        "branch" => branch,
        "sha" => cleanup_sha,
        "reconciled_generated_commit" => !reconciliation.nil?,
        "commit_verification" => reconciliation && reconciliation["verification"],
        "closed_pull_requests" => pulls.map { |pull| Integer(pull.fetch("number")) },
        "deleted" => true
      }
    end

    def create_release(tag:, target_sha:, title:, body:)
      request!("POST", "/repos/#{@repository}/releases", body: {
        "tag_name" => tag,
        "target_commitish" => target_sha,
        "name" => title,
        "body" => body,
        "draft" => false,
        "prerelease" => true,
        "make_latest" => "false"
      })
    end

    def update_release(id:, title:, prerelease:, make_latest:)
      request!("PATCH", "/repos/#{@repository}/releases/#{Integer(id)}", body: {
        "name" => title,
        "prerelease" => prerelease,
        "make_latest" => make_latest ? "true" : "false"
      })
    end

    def upload_release_asset(release:, path:, name: File.basename(path))
      bytes = File.binread(path)
      digest = Digest::SHA256.hexdigest(bytes)
      existing = Array(release["assets"]).find { |asset| asset["name"] == name }
      if existing
        existing_digest = existing["digest"].to_s.delete_prefix("sha256:")
        raise ValidationError, "release asset #{name} already exists with a different checksum" unless existing_digest == digest

        return existing
      end
      transport = HTTPTransport.new(
        base_url: UPLOAD_URL,
        default_headers: {
          "Accept" => "application/vnd.github+json",
          "Authorization" => "Bearer #{@token}",
          "Content-Type" => "application/zip",
          "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent" => "sequel-ace-release-tool"
        }
      )
      response = transport.request(
        "POST",
        "/repos/#{@repository}/releases/#{release.fetch('id')}/assets",
        query: { "name" => name },
        body: bytes
      )
      ensure_response!(response, [201])
    end

    private

    def verified_commit_evidence(commit)
      validate_commit_sha!(commit.fetch("oid"), "created release commit SHA")
      signature = commit.fetch("signature", {}) || {}
      verified = github_signature_valid?(signature)
      unless verified
        raise ValidationError, "GitHub did not verify the release bot commit: #{signature['state'] || 'missing signature'}"
      end

      {
        "sha" => commit.fetch("oid"),
        "html_url" => commit.fetch("url"),
        "verification" => {
          "verified" => true,
          "reason" => "valid",
          "was_signed_by_github" => true
        }
      }
    end

    def inspect_generated_commit!(branch:, base_sha:, repository_root:, changed_paths:, require_github_signature:)
      validate_commit_sha!(base_sha, "release base SHA")
      actual_sha = ref_sha("heads/#{branch}")
      validate_commit_sha!(actual_sha, "release branch SHA")
      raise ValidationError, "release branch did not advance beyond its base" if actual_sha == base_sha

      owner, name = @repository.split("/", 2)
      data = graphql!(INSPECT_COMMIT_QUERY, {
        "owner" => owner,
        "name" => name,
        "oid" => actual_sha
      })
      commit = data.dig("repository", "object")
      unless commit.is_a?(Hash) && commit["oid"] == actual_sha
        raise ValidationError, "GitHub could not resolve the generated release commit"
      end
      parents = Array(commit.dig("parents", "nodes")).map { |parent| parent["oid"] }
      unless parents == [base_sha]
        raise ValidationError, "generated release commit does not have the frozen main as its only parent"
      end

      signature = commit["signature"] || {}
      signature_valid = github_signature_valid?(signature)
      if require_github_signature && !signature_valid
        raise ValidationError, "GitHub did not verify the reconciled release bot commit: #{signature['state'] || 'missing signature'}"
      end

      comparison = request!("GET", "/repos/#{@repository}/compare/#{base_sha}...#{actual_sha}")
      commits = Array(comparison["commits"]).map { |value| value["sha"] }
      topology_valid = comparison["status"] == "ahead" && comparison["ahead_by"] == 1 &&
                       comparison["behind_by"] == 0 && comparison["total_commits"] == 1 &&
                       comparison.dig("merge_base_commit", "sha") == base_sha && commits == [actual_sha]
      raise ValidationError, "generated release branch is not exactly one commit above frozen main" unless topology_valid

      expected_files = expected_release_files(repository_root, changed_paths)
      actual_files = Array(comparison["files"]).each_with_object({}) do |file, result|
        result[file.fetch("filename")] = file
      end
      unless actual_files.keys.sort == expected_files.keys.sort
        raise ValidationError, "generated release commit changed unexpected files"
      end
      expected_files.each do |path, expected|
        actual = actual_files.fetch(path)
        unless actual["status"] == expected.fetch("status")
          raise ValidationError, "generated release commit has an unexpected status for #{path}"
        end
        next if expected["sha"].nil?

        unless actual["sha"] == expected.fetch("sha")
          raise ValidationError, "generated release commit content does not match #{path}"
        end
      end

      {
        "sha" => actual_sha,
        "html_url" => commit["url"],
        "verification" => {
          "verified" => signature_valid,
          "reason" => signature["state"].to_s.downcase,
          "was_signed_by_github" => signature["wasSignedByGitHub"] == true
        },
        "reconciled" => true
      }
    end

    def expected_release_files(repository_root, changed_paths)
      Array(changed_paths).each_with_object({}) do |change, result|
        path = change.fetch("path")
        validate_release_path!(path)
        raise ValidationError, "release preparation listed #{path} more than once" if result.key?(path)

        local_status = change.fetch("status")
        if local_status.include?("D")
          result[path] = { "status" => "removed", "sha" => nil }
        else
          remote_status = local_status.include?("?") || local_status.include?("A") ? "added" : "modified"
          bytes = File.binread(File.join(repository_root, path))
          result[path] = { "status" => remote_status, "sha" => git_blob_sha(bytes) }
        end
      end
    end

    def git_blob_sha(bytes)
      Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes.b)
    end

    def github_signature_valid?(signature)
      signature["isValid"] == true && signature["wasSignedByGitHub"] == true && signature["state"] == "VALID"
    end

    def validate_commit_sha!(value, label)
      return if value.to_s.match?(/\A[0-9a-f]{40,64}\z/i)

      raise ValidationError, "#{label} is malformed"
    end

    def paginate(path, query, data_key: nil)
      values = []
      next_path = path
      next_query = query
      while next_path
        response = @transport.request("GET", next_path, query: next_query)
        body = ensure_response!(response, [200])
        page = data_key ? body.fetch(data_key, []) : body
        values.concat(page)
        next_link = Array(response.headers["link"]).first.to_s.split(",").find { |part| part.include?('rel="next"') }
        next_path = next_link&.match(/<([^>]+)>/)&.captures&.first
        next_query = nil
      end
      values
    end

    def request!(method, path, body: nil, expected: nil)
      response = @transport.request(method, path, body: body, headers: body.nil? ? {} : { "Content-Type" => "application/json" })
      ensure_response!(response, expected || success_codes(method))
    end

    def graphql!(query, variables)
      response = @transport.request(
        "POST",
        "/graphql",
        body: { "query" => query, "variables" => variables },
        headers: { "Content-Type" => "application/json" }
      )
      body = ensure_response!(response, [200])
      raise APIError, "GitHub GraphQL API returned a malformed response" unless body.is_a?(Hash)

      errors = Array(body["errors"])
      unless errors.empty?
        messages = errors.filter_map { |error| error["message"] if error.is_a?(Hash) }
        raise APIError, "GitHub GraphQL API returned errors#{messages.empty? ? '' : ": #{messages.join('; ')}"}"
      end

      data = body.fetch("data")
      raise APIError, "GitHub GraphQL API returned a malformed response" unless data.is_a?(Hash)

      data
    rescue KeyError
      raise APIError, "GitHub GraphQL API returned a malformed response"
    end

    def ensure_response!(response, expected)
      return response.body if expected.include?(response.status)

      message = response.body.is_a?(Hash) ? response.body["message"] : nil
      raise APIError, "GitHub API returned HTTP #{response.status}#{message ? ": #{message}" : ''}"
    end

    def success_codes(method)
      method.to_s.upcase == "DELETE" ? [204] : (200..299).to_a
    end

    def check_run_order(run)
      timestamp = run["started_at"] || run["created_at"] || run["completed_at"] || ""
      [timestamp.to_s, run["id"].to_i]
    end

    def validate_release_path!(path)
      allowed = Config::PROJECT_FILES.keys + Config::PLIST_FILES + ["CHANGELOG.md"]
      return if allowed.include?(path)

      raise ValidationError, "release preparation changed an unauthorized path: #{path}"
    end

    def open_pull_requests_for_branch(branch)
      owner = @repository.split("/", 2).first
      response = @transport.request("GET", "/repos/#{@repository}/pulls", query: {
        "state" => "open",
        "head" => "#{owner}:#{branch}",
        "per_page" => 100
      })
      Array(ensure_response!(response, [200]))
    end
  end
end
