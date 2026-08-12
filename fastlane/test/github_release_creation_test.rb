# frozen_string_literal: true

require "test_helper"

class GitHubReleaseCreationTest < Minitest::Test
  class Client
    attr_reader :events

    def initialize
      @events = []
    end

    def validate_release_target!(target_sha:, protected_paths:)
      raise "wrong target" unless target_sha == "a" * 40
      raise "missing protected paths" if protected_paths.empty?

      @events << :validate_target
      { "target_sha" => target_sha }
    end

    def create_or_validate_release_tag(tag:, target_sha:)
      raise "wrong tag" unless tag == "production/5.4.0-20105"
      raise "wrong target" unless target_sha == "a" * 40

      @events << :create_tag
      {
        "ref" => "refs/tags/#{tag}",
        "object" => { "type" => "commit", "sha" => target_sha },
        "created" => true
      }
    end

    def create_or_validate_release(tag:, target_sha:, title:, body:)
      raise "tag was not created first" unless @events == %i[validate_target create_tag]
      raise "wrong tag" unless tag == "production/5.4.0-20105"
      raise "wrong target" unless target_sha == "a" * 40
      raise "wrong title" unless title == "5.4.0 (20105) - Release Candidate 1"
      raise "wrong body" unless body == "Approved notes"

      @events << :publish_release
      { "id" => 100, "tag_name" => tag, "created" => true }
    end

    def validate_release_tag(tag:, target_sha:)
      raise "wrong tag" unless tag == "production/5.4.0-20105"
      raise "wrong target" unless target_sha == "a" * 40

      @events << :verify_tag
      {
        "ref" => "refs/tags/#{tag}",
        "object" => { "type" => "commit", "sha" => target_sha }
      }
    end
  end

  def test_cli_creates_the_exact_tag_before_publishing_the_prerelease
    client = Client.new
    output = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: StringIO.new, env: {})

    Dir.mktmpdir do |directory|
      body = File.join(directory, "release-body.md")
      File.write(body, "Approved notes")
      status = cli.stub(:github_client, client) do
        cli.run([
          "github-create-release",
          "--channel", "production",
          "--version", "5.4.0",
          "--build", "20105",
          "--iteration", "1",
          "--target-sha", "a" * 40,
          "--body", body
        ])
      end

      assert_equal 0, status
    end

    assert_equal %i[validate_target create_tag publish_release], client.events
    result = JSON.parse(output.string)
    assert_equal true, result.dig("tag", "created")
    assert_equal 100, result.dig("release", "id")
  end

  def test_cli_verifies_the_exact_existing_release_tag
    client = Client.new
    output = StringIO.new
    cli = SequelAceRelease::CLI.new(out: output, err: StringIO.new, env: {})

    status = cli.stub(:github_client, client) do
      cli.run([
        "github-verify-release-tag",
        "--tag", "production/5.4.0-20105",
        "--target-sha", "a" * 40
      ])
    end

    assert_equal 0, status
    assert_equal [:verify_tag], client.events
    assert_equal "a" * 40, JSON.parse(output.string).dig("object", "sha")
  end
end
