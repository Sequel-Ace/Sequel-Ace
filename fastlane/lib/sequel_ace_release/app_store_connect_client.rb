# frozen_string_literal: true

require "base64"
require "jwt"
require "openssl"

module SequelAceRelease
  class AppStoreConnectClient
    API_URL = "https://api.appstoreconnect.apple.com/"

    def initialize(key_id:, private_key:, issuer_id: nil, transport: nil, clock: -> { Time.now })
      raise ValidationError, "App Store Connect key ID is required" if key_id.to_s.empty?
      raise ValidationError, "App Store Connect private key is required" if private_key.to_s.empty?

      @key_id = key_id
      @private_key = private_key
      @issuer_id = issuer_id.to_s.empty? ? nil : issuer_id
      @clock = clock
      @transport = transport || HTTPTransport.new(
        base_url: API_URL,
        default_headers: {
          "Accept" => "application/json",
          "User-Agent" => "sequel-ace-release-tool"
        }
      )
    end

    def self.from_env(environment = ENV)
      private_key = environment["SA_ASC_PRIVATE_KEY"]
      issuer_id = environment["SA_ASC_ISSUER_ID"]
      if environment["SA_ASC_REQUIRE_ISSUER"] == "1" && issuer_id.to_s.empty?
        raise ValidationError, "App Store Connect issuer ID is required for the configured Team API key"
      end
      if environment["SA_ASC_PRIVATE_KEY_BASE64"] == "1" && !private_key.to_s.empty?
        private_key = Base64.strict_decode64(private_key)
      end
      new(
        key_id: environment["SA_ASC_KEY_ID"],
        issuer_id: issuer_id,
        private_key: private_key
      )
    rescue ArgumentError
      raise ValidationError, "App Store Connect private key is not valid base64"
    end

    def workflow_runs(workflow_id)
      resources = paginate("/v1/ciWorkflows/#{workflow_id}/buildRuns", {
        "limit" => 200,
        "sort" => "-number"
      })
      resources.map { |resource| normalize_run(resource) }
    end

    def build_run(run_id)
      body = ensure_response!(api_request("GET", "/v1/ciBuildRuns/#{run_id}", query: {
        "include" => "workflow,sourceBranchOrTag",
        "fields[scmGitReferences]" => "name,canonicalName,kind"
      }))
      resource = body.fetch("data")
      included = Array(body["included"])
      reference_id = resource.dig("relationships", "sourceBranchOrTag", "data", "id")
      reference = included.find { |candidate| candidate["type"] == "scmGitReferences" && candidate["id"] == reference_id }
      workflow_id = resource.dig("relationships", "workflow", "data", "id")
      normalize_run(resource).merge(
        "workflow_id" => workflow_id,
        "git_reference_id" => reference_id,
        "git_reference" => normalize_git_reference(reference)
      ).compact
    end

    def start_cloud_run(workflow_id:, git_reference_id:)
      body = ensure_response!(api_request("POST", "/v1/ciBuildRuns", body: {
        "data" => {
          "type" => "ciBuildRuns",
          "attributes" => {},
          "relationships" => {
            "workflow" => { "data" => { "type" => "ciWorkflows", "id" => workflow_id } },
            "sourceBranchOrTag" => { "data" => { "type" => "scmGitReferences", "id" => git_reference_id } }
          }
        }
      }))
      body.fetch("data")
    end

    def app(app_id)
      response_data("GET", "/v1/apps/#{app_id}")
    end

    def run_actions(run_id)
      paginate("/v1/ciBuildRuns/#{run_id}/actions", { "limit" => 200 })
    end

    def action_artifacts(action_id)
      paginate("/v1/ciBuildActions/#{action_id}/artifacts", { "limit" => 200 })
    end

    def run_artifacts(run_id)
      run_actions(run_id).flat_map { |action| action_artifacts(action.fetch("id")) }
    end

    def run_builds(run_id)
      paginate("/v1/ciBuildRuns/#{run_id}/builds", { "limit" => 200 })
    end

    def cloud_builds_for_run(run_id)
      run_builds(run_id).map do |build|
        app_resource = response_data("GET", "/v1/builds/#{build.fetch('id')}/app")
        pre_release = response_data("GET", "/v1/builds/#{build.fetch('id')}/preReleaseVersion")
        {
          "id" => build.fetch("id"),
          "app_id" => app_resource&.fetch("id", nil),
          "version" => pre_release&.dig("attributes", "version"),
          "platform" => pre_release&.dig("attributes", "platform"),
          "build" => integer_or_nil(build.dig("attributes", "version"))
        }.compact
      end
    end

    def highest_app_build(app_id)
      builds = paginate("/v1/builds", {
        "filter[app]" => app_id,
        "limit" => 200,
        "sort" => "-uploadedDate"
      })
      builds.filter_map { |build| integer_or_nil(build.dig("attributes", "version")) }.max || 0
    end

    def find_build(app_id:, version:, build:)
      builds = paginate("/v1/builds", {
        "filter[app]" => app_id,
        "filter[version]" => build.to_s,
        "filter[preReleaseVersion.version]" => version,
        "include" => "preReleaseVersion",
        "limit" => 200
      })
      builds.find { |resource| resource.dig("attributes", "version").to_s == build.to_s }
    end

    def app_store_version(app_id:, version:)
      paginate("/v1/apps/#{app_id}/appStoreVersions", {
        "filter[platform]" => "MAC_OS",
        "filter[versionString]" => version,
        "limit" => 10
      }).first
    end

    def app_store_versions(app_id:)
      paginate("/v1/apps/#{app_id}/appStoreVersions", {
        "filter[platform]" => "MAC_OS",
        "limit" => 200
      })
    end

    def latest_released_version(app_id:)
      app_store_versions(app_id: app_id)
        .select { |resource| app_version_state(resource) == "READY_FOR_DISTRIBUTION" }
        .max_by { |resource| Version.parts(resource.dig("attributes", "versionString")) }
    end

    def localization(version_id:, locale: Config::LOCALE)
      paginate("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations", {
        "filter[locale]" => locale,
        "limit" => 10
      }).first
    end

    def screenshot_sets(localization_id:)
      sets = paginate("/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets", {
        "limit" => 200
      })
      sets.map do |set|
        set.merge("screenshots" => paginate("/v1/appScreenshotSets/#{set.fetch('id')}/appScreenshots", { "limit" => 200 }))
      end
    end

    def review_detail(version_id:)
      response_data("GET", "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")
    rescue APIError => e
      raise unless e.message.include?("HTTP 404")

      nil
    end

    def phased_release(version_id:)
      response_data("GET", "/v1/appStoreVersions/#{version_id}/appStoreVersionPhasedRelease")
    rescue APIError => e
      raise unless e.message.include?("HTTP 404")

      nil
    end

    def selected_build(version_id:)
      response_data("GET", "/v1/appStoreVersions/#{version_id}/build")
    rescue APIError => e
      raise unless e.message.include?("HTTP 404")

      nil
    end

    def reset_ratings_request(version_id:)
      response_data("GET", "/v1/appStoreVersions/#{version_id}/resetRatingsRequest")
    rescue APIError => e
      raise unless e.message.include?("HTTP 404")

      nil
    end

    def attach_build(version_id:, build_id:)
      response = api_request("PATCH", "/v1/appStoreVersions/#{version_id}/relationships/build", body: {
        "data" => { "type" => "builds", "id" => build_id }
      })
      ensure_response!(response)
      true
    end

    def metadata_snapshot(app_id:, version:)
      version_resource = app_store_version(app_id: app_id, version: version)
      raise ValidationError, "App Store version #{version} does not exist" unless version_resource

      localization_resource = localization(version_id: version_resource.fetch("id"))
      raise ValidationError, "#{Config::LOCALE} localization does not exist for #{version}" unless localization_resource

      {
        "version" => version_resource,
        "localization" => localization_resource,
        "screenshot_sets" => screenshot_sets(localization_id: localization_resource.fetch("id")),
        "review_detail" => review_detail(version_id: version_resource.fetch("id")),
        "phased_release" => phased_release(version_id: version_resource.fetch("id")),
        "selected_build" => selected_build(version_id: version_resource.fetch("id")),
        "reset_ratings_request" => reset_ratings_request(version_id: version_resource.fetch("id"))
      }
    end

    def find_cloud_run(workflow_id:, commit: nil, tag: nil, run_id: nil)
      candidates = if run_id
                     [build_run(run_id)]
                   else
                     workflow_runs(workflow_id).filter_map do |item|
                       next if commit && ![item["source_commit"], item["destination_commit"]].compact.include?(commit)

                       build_run(item.fetch("id"))
                     end
                   end
      candidates.find do |run|
        next false unless run["workflow_id"] == workflow_id
        next false if commit && ![run["source_commit"], run["destination_commit"]].compact.include?(commit)
        next false if tag && run["git_reference"] != tag

        true
      end
    end

    private

    def token
      now = @clock.call.to_i
      payload = { "aud" => "appstoreconnect-v1", "iat" => now - 60, "exp" => now + 1_140 }
      if @issuer_id
        payload["iss"] = @issuer_id
      else
        payload["sub"] = "user"
      end
      key = OpenSSL::PKey.read(@private_key)
      JWT.encode(payload, key, "ES256", { "kid" => @key_id, "typ" => "JWT" })
    rescue OpenSSL::PKey::PKeyError => e
      raise ValidationError, "invalid App Store Connect private key: #{e.message}"
    end

    def paginate(path, query)
      resources = []
      next_path = path
      next_query = query
      while next_path
        response = api_request("GET", next_path, query: next_query)
        body = ensure_response!(response)
        resources.concat(Array(body["data"]))
        next_path = body.dig("links", "next")
        next_query = nil
      end
      resources
    end

    def response_data(method, path)
      ensure_response!(api_request(method, path))["data"]
    end

    def api_request(method, path, query: nil, body: nil)
      headers = { "Authorization" => "Bearer #{token}" }
      headers["Content-Type"] = "application/json" if body
      @transport.request(method, path, query: query, body: body, headers: headers)
    end

    def ensure_response!(response)
      return response.body if (200..299).cover?(response.status)

      errors = response.body.is_a?(Hash) ? Array(response.body["errors"]).map { |error| error["detail"] || error["title"] }.compact : []
      suffix = errors.empty? ? "" : ": #{errors.join('; ')}"
      raise APIError, "App Store Connect API returned HTTP #{response.status}#{suffix}"
    end

    def normalize_run(resource)
      attributes = resource.fetch("attributes", {})
      source = attributes["sourceCommit"] || {}
      destination = attributes["destinationCommit"] || {}
      {
        "id" => resource["id"],
        "number" => integer_or_nil(attributes["number"]),
        "execution_progress" => attributes["executionProgress"],
        "completion_status" => attributes["completionStatus"],
        "created_date" => attributes["createdDate"],
        "started_date" => attributes["startedDate"],
        "finished_date" => attributes["finishedDate"],
        "source_commit" => source["commitSha"] || source["sha"],
        "destination_commit" => destination["commitSha"] || destination["sha"]
      }.compact
    end

    def normalize_git_reference(resource)
      value = resource&.dig("attributes", "canonicalName") || resource&.dig("attributes", "name")
      value.to_s.delete_prefix("refs/tags/").delete_prefix("refs/heads/") unless value.to_s.empty?
    end

    def integer_or_nil(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def app_version_state(resource)
      attributes = resource.fetch("attributes", {})
      attributes["appVersionState"] || attributes["appStoreState"]
    end

  end
end
