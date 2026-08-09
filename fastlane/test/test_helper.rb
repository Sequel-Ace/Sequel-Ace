# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "sequel_ace_release"

module ReleaseTestHelpers
  class FakeTransport
    attr_reader :requests

    def initialize(responses)
      @responses = responses.dup
      @requests = []
    end

    def request(method, path, query: nil, body: nil, headers: {})
      @requests << { method: method, path: path, query: query, body: body, headers: headers }
      response = @responses.shift
      raise "no fake response left for #{method} #{path}" unless response

      response.respond_to?(:call) ? response.call(@requests.last) : response
    end
  end

  def http_response(status: 200, body: {}, headers: {})
    SequelAceRelease::HTTPTransport::Response.new(status: status, body: body, headers: headers)
  end

  def fixture_json(path)
    JSON.parse(File.read(File.join(__dir__, "fixtures", path)))
  end

  def approval(overrides = {})
    SequelAceRelease::Approval.new(**{
      channel: "production",
      target_version: "5.3.2",
      main_sha: "a" * 40,
      previous_tag: "production/5.3.1-20104",
      base_sha: "b" * 40,
      app_store_notes: "A focused release note.",
      release_notes_sha256: "c" * 64,
      observed_production_cloud_next_build: 20_105
    }.merge(overrides))
  end

  def complete_screenshots(count = 10)
    Array.new(count) do |index|
      {
        "id" => "screenshot-#{index}",
        "attributes" => { "assetDeliveryState" => { "state" => "COMPLETE" } }
      }
    end
  end

  def metadata_snapshot(build: 20_105, state: "PREPARE_FOR_SUBMISSION", phased_state: "INACTIVE")
    {
      "version" => {
        "id" => "version-id",
        "attributes" => {
          "appStoreState" => state,
          "releaseType" => "SCHEDULED",
          "earliestReleaseDate" => "2026-08-12T16:00:00Z"
        }
      },
      "localization" => {
        "id" => "localization-id",
        "attributes" => {
          "locale" => "en-US",
          "description" => "Description",
          "keywords" => "mysql,database",
          "whatsNew" => "A focused release note.",
          "promotionalText" => "A native database client.",
          "supportUrl" => "https://sequel-ace.com/support",
          "marketingUrl" => "https://sequel-ace.com"
        }
      },
      "screenshot_sets" => [{ "id" => "set-id", "screenshots" => complete_screenshots }],
      "review_detail" => {
        "id" => "review-id",
        "attributes" => {
          "contactFirstName" => "Release",
          "contactLastName" => "Manager",
          "contactEmail" => "release@example.invalid",
          "contactPhone" => "+10000000000",
          "demoAccountRequired" => false
        }
      },
      "phased_release" => {
        "id" => "phase-id",
        "attributes" => { "phasedReleaseState" => phased_state }
      },
      "selected_build" => {
        "id" => "build-id",
        "attributes" => { "version" => build.to_s }
      },
      "reset_ratings_request" => nil
    }
  end
end

class Minitest::Test
  include ReleaseTestHelpers
end
