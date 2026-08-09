# frozen_string_literal: true

require "base64"
require "digest"
require "uri"

module SequelAceRelease
  class GitHubClient
    API_URL = "https://api.github.com/"
    UPLOAD_URL = "https://uploads.github.com/"

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

      base_commit = request!("GET", "/repos/#{@repository}/git/commits/#{base_sha}")
      entries = changed_paths.map do |change|
        path = change.fetch("path")
        validate_release_path!(path)
        if change.fetch("status").include?("D")
          { "path" => path, "mode" => "100644", "type" => "blob", "sha" => nil }
        else
          bytes = File.binread(File.join(repository_root, path))
          blob = request!("POST", "/repos/#{@repository}/git/blobs", body: {
            "content" => Base64.strict_encode64(bytes),
            "encoding" => "base64"
          })
          { "path" => path, "mode" => "100644", "type" => "blob", "sha" => blob.fetch("sha") }
        end
      end

      tree = request!("POST", "/repos/#{@repository}/git/trees", body: {
        "base_tree" => base_commit.fetch("tree").fetch("sha"),
        "tree" => entries
      })
      commit = request!("POST", "/repos/#{@repository}/git/commits", body: {
        "message" => message,
        "tree" => tree.fetch("sha"),
        "parents" => [base_sha]
      })
      verification = commit.fetch("verification", {})
      unless verification["verified"] == true
        raise ValidationError, "GitHub did not verify the release bot commit: #{verification['reason'] || 'unknown reason'}"
      end

      request!("POST", "/repos/#{@repository}/git/refs", body: {
        "ref" => "refs/heads/#{branch}",
        "sha" => commit.fetch("sha")
      })
      commit
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
  end
end
