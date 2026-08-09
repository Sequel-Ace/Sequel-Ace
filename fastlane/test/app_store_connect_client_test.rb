# frozen_string_literal: true

require "test_helper"

class AppStoreConnectClientTest < Minitest::Test
  def test_normalizes_cloud_runs_and_uses_individual_key_jwt
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(body: {
        "data" => [{
          "id" => "run-id",
          "attributes" => {
            "number" => 20_105,
            "executionProgress" => "COMPLETE",
            "completionStatus" => "SUCCEEDED",
            "sourceCommit" => { "commitSha" => "a" * 40 }
          }
        }],
        "links" => { "next" => nil }
      })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      issuer_id: nil,
      private_key: key.to_pem,
      transport: transport,
      clock: -> { Time.at(1_700_000_000) }
    )

    runs = client.workflow_runs("workflow-id")
    assert_equal 20_105, runs.first.fetch("number")
    assert_equal "a" * 40, runs.first.fetch("source_commit")
    authorization = transport.requests.first.dig(:headers, "Authorization")
    token = authorization.delete_prefix("Bearer ")
    payload, header = JWT.decode(token, nil, false)
    refute payload.key?("iss")
    assert_equal "user", payload.fetch("sub")
    assert_equal "appstoreconnect-v1", payload.fetch("aud")
    assert_equal "KEY123", header.fetch("kid")
    assert_equal "-number", transport.requests.first.dig(:query, "sort")
  end

  def test_reads_an_exact_app_resource
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(body: { "data" => { "id" => "1518036000", "type" => "apps" } })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    assert_equal "1518036000", client.app("1518036000").fetch("id")
    assert_equal "/v1/apps/1518036000", transport.requests.first.fetch(:path)
  end

  def test_reads_detailed_cloud_run_workflow_commit_and_tag
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(body: {
        "data" => {
          "id" => "run-id",
          "attributes" => {
            "number" => 20_105,
            "sourceCommit" => { "commitSha" => "a" * 40 }
          },
          "relationships" => {
            "workflow" => { "data" => { "type" => "ciWorkflows", "id" => "workflow-id" } },
            "sourceBranchOrTag" => { "data" => { "type" => "scmGitReferences", "id" => "ref-id" } }
          }
        },
        "included" => [{
          "type" => "scmGitReferences",
          "id" => "ref-id",
          "attributes" => { "canonicalName" => "refs/tags/production/5.3.2-20105", "kind" => "TAG" }
        }]
      })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    run = client.build_run("run-id")
    assert_equal "workflow-id", run.fetch("workflow_id")
    assert_equal "ref-id", run.fetch("git_reference_id")
    assert_equal "production/5.3.2-20105", run.fetch("git_reference")
    assert_equal "a" * 40, run.fetch("source_commit")
  end

  def test_finds_an_exact_cloud_run_by_id_and_validates_every_identity_field
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(body: {
        "data" => {
          "id" => "run-id",
          "attributes" => {
            "number" => 20_105,
            "sourceCommit" => { "commitSha" => "a" * 40 }
          },
          "relationships" => {
            "workflow" => { "data" => { "type" => "ciWorkflows", "id" => "workflow-id" } },
            "sourceBranchOrTag" => { "data" => { "type" => "scmGitReferences", "id" => "ref-id" } }
          }
        },
        "included" => [{
          "type" => "scmGitReferences",
          "id" => "ref-id",
          "attributes" => { "canonicalName" => "refs/tags/production/5.3.2-20105", "kind" => "TAG" }
        }]
      })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    run = client.find_cloud_run(
      workflow_id: "workflow-id",
      run_id: "run-id",
      build: 20_105,
      commit: "a" * 40,
      tag: "production/5.3.2-20105"
    )

    assert_equal "run-id", run.fetch("id")
    assert_equal "/v1/ciBuildRuns/run-id", transport.requests.first.fetch(:path)
  end

  def test_find_cloud_run_does_not_let_a_newer_branch_run_mask_the_exact_tag_run
    key = OpenSSL::PKey::EC.generate("prime256v1")
    summary = lambda do |id, number|
      {
        "id" => id,
        "attributes" => {
          "number" => number,
          "sourceCommit" => { "commitSha" => "a" * 40 }
        }
      }
    end
    detail = lambda do |id, number, reference_id, canonical_name|
      {
        "data" => {
          "id" => id,
          "attributes" => {
            "number" => number,
            "sourceCommit" => { "commitSha" => "a" * 40 }
          },
          "relationships" => {
            "workflow" => { "data" => { "type" => "ciWorkflows", "id" => "workflow-id" } },
            "sourceBranchOrTag" => { "data" => { "type" => "scmGitReferences", "id" => reference_id } }
          }
        },
        "included" => [{
          "type" => "scmGitReferences",
          "id" => reference_id,
          "attributes" => { "canonicalName" => canonical_name, "kind" => "TAG" }
        }]
      }
    end
    transport = FakeTransport.new([
      http_response(body: {
        "data" => [summary.call("newer-main-run", 20_106), summary.call("exact-tag-run", 20_105)],
        "links" => { "next" => nil }
      }),
      http_response(body: detail.call("newer-main-run", 20_106, "main-ref", "refs/heads/main")),
      http_response(body: detail.call("exact-tag-run", 20_105, "tag-ref", "refs/tags/beta/5.3.2-20105"))
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    run = client.find_cloud_run(
      workflow_id: "workflow-id",
      commit: "a" * 40,
      tag: "beta/5.3.2-20105"
    )

    assert_equal "exact-tag-run", run.fetch("id")
  end

  def test_cloud_run_builds_include_exact_app_marketing_version_and_build
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(body: {
        "data" => [{ "id" => "build-id", "attributes" => { "version" => "20105" } }],
        "links" => { "next" => nil }
      }),
      http_response(body: { "data" => { "id" => "1518036000", "type" => "apps" } }),
      http_response(body: {
        "data" => { "id" => "pre-release-id", "attributes" => { "version" => "5.3.2", "platform" => "MAC_OS" } }
      })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    assert_equal({
      "id" => "build-id",
      "app_id" => "1518036000",
      "version" => "5.3.2",
      "platform" => "MAC_OS",
      "build" => 20_105
    }, client.cloud_builds_for_run("run-id").first)
  end

  def test_starts_an_alpha_retry_with_the_exact_workflow_and_tag_relationship
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(status: 201, body: { "data" => { "type" => "ciBuildRuns", "id" => "retry-run-id" } })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    assert_equal "retry-run-id", client.start_cloud_run(
      workflow_id: "alpha-workflow-id",
      git_reference_id: "tag-reference-id"
    ).fetch("id")
    relationships = transport.requests.first.fetch(:body).dig("data", "relationships")
    assert_equal "alpha-workflow-id", relationships.dig("workflow", "data", "id")
    assert_equal "tag-reference-id", relationships.dig("sourceBranchOrTag", "data", "id")
  end

  def test_attach_build_uses_exact_relationship_endpoint
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([http_response(status: 204, body: nil)])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    assert client.attach_build(version_id: "version-id", build_id: "build-id")
    request = transport.requests.first
    assert_equal "PATCH", request[:method]
    assert_equal "/v1/appStoreVersions/version-id/relationships/build", request[:path]
    assert_equal({ "type" => "builds", "id" => "build-id" }, request[:body].fetch("data"))
  end

  def test_metadata_snapshot_passes_version_ids_as_keywords
    key = OpenSSL::PKey::EC.generate("prime256v1")
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: FakeTransport.new([])
    )
    client.define_singleton_method(:app_store_version) do |app_id:, version:|
      raise unless app_id == "1518036000" && version == "5.3.2"

      { "id" => "version-id" }
    end
    client.define_singleton_method(:localization) do |version_id:, locale: SequelAceRelease::Config::LOCALE|
      raise unless version_id == "version-id" && locale == "en-US"

      { "id" => "localization-id" }
    end
    client.define_singleton_method(:screenshot_sets) do |localization_id:|
      raise unless localization_id == "localization-id"

      []
    end
    %i[review_detail phased_release selected_build reset_ratings_request].each do |method|
      client.define_singleton_method(method) do |version_id:|
        raise unless version_id == "version-id"

        { "id" => method.to_s }
      end
    end

    snapshot = client.metadata_snapshot(app_id: "1518036000", version: "5.3.2")
    assert_equal "review_detail", snapshot.dig("review_detail", "id")
    assert_equal "selected_build", snapshot.dig("selected_build", "id")
  end

  def test_find_build_filters_by_both_marketing_version_and_build_number
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(body: {
        "data" => [{ "id" => "build-id", "attributes" => { "version" => "20105" } }],
        "links" => { "next" => nil }
      })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    assert_equal "build-id", client.find_build(app_id: "1518036000", version: "5.3.2", build: 20_105).fetch("id")
    query = transport.requests.first.fetch(:query)
    assert_equal "20105", query.fetch("filter[version]")
    assert_equal "5.3.2", query.fetch("filter[preReleaseVersion.version]")
  end

  def test_api_errors_redact_credentials
    key = OpenSSL::PKey::EC.generate("prime256v1")
    transport = FakeTransport.new([
      http_response(status: 403, body: { "errors" => [{ "detail" => "Not authorized" }] })
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "SECRETKEY",
      private_key: key.to_pem,
      transport: transport
    )

    error = assert_raises(SequelAceRelease::APIError) { client.workflow_runs("workflow-id") }
    assert_includes error.message, "HTTP 403"
    refute_includes error.message, "SECRETKEY"
    refute_includes error.message, "PRIVATE KEY"
  end

  def test_cloud_run_pagination_uses_redacted_recorded_fixtures
    key = OpenSSL::PKey::EC.generate("prime256v1")
    first = fixture_json("app_store_connect/cloud-runs-page-1.json")
    second = fixture_json("app_store_connect/cloud-runs-page-2.json")
    transport = FakeTransport.new([
      http_response(body: first),
      http_response(body: second)
    ])
    client = SequelAceRelease::AppStoreConnectClient.new(
      key_id: "KEY123",
      private_key: key.to_pem,
      transport: transport
    )

    assert_equal [20_105, 20_104], client.workflow_runs("workflow-id").map { |run| run.fetch("number") }
    assert_equal first.dig("links", "next"), transport.requests.last.fetch(:path)
    assert_nil transport.requests.last[:query]
  end
end
