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

    def validate_release_publisher!(expected_login:)
      raise "wrong publisher" unless expected_login == SequelAceRelease::ReleasePublisher::USER_LOGIN

      @events << :validate_publisher
      { "login" => expected_login, "repository" => SequelAceRelease::Config::REPOSITORY, "push_access" => true }
    end

    def validate_release_app_publisher!(expected_app_id:)
      raise "wrong release App" unless expected_app_id == SequelAceRelease::ReleasePublisher::RELEASE_APP_ID

      @events << :validate_app_publisher
      {
        "login" => SequelAceRelease::ReleasePublisher::RELEASE_APP_LOGIN,
        "app_id" => expected_app_id,
        "repository" => SequelAceRelease::Config::REPOSITORY,
        "push_access" => true
      }
    end

    def create_or_validate_release_tag(tag:, target_sha:)
      raise "wrong tag" unless tag == "production/5.4.0-20109"
      raise "wrong target" unless target_sha == "a" * 40

      @events << :create_tag
      {
        "ref" => "refs/tags/#{tag}",
        "object" => { "type" => "commit", "sha" => target_sha },
        "created" => true
      }
    end

    def create_or_validate_release(tag:, target_sha:, title:, body:, expected_author_login:)
      expected_events = if expected_author_login == SequelAceRelease::ReleasePublisher::USER_LOGIN
                          %i[validate_target validate_publisher create_tag]
                        else
                          %i[validate_target validate_app_publisher create_tag]
                        end
      raise "tag was not created first" unless @events == expected_events
      raise "wrong tag" unless tag == "production/5.4.0-20109"
      raise "wrong target" unless target_sha == "a" * 40
      raise "wrong title" unless title == "5.4.0 (20109) - Release Candidate 1"
      raise "wrong body" unless body == "Approved notes"
      unless [
        SequelAceRelease::ReleasePublisher::USER_LOGIN,
        SequelAceRelease::ReleasePublisher::RELEASE_APP_LOGIN
      ].include?(expected_author_login)
        raise "wrong release author"
      end

      @events << :publish_release
      created_at = if expected_author_login == SequelAceRelease::ReleasePublisher::USER_LOGIN
                     "2026-08-13T00:00:00Z"
                   else
                     SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF.iso8601
                   end
      {
        "id" => 100,
        "tag_name" => tag,
        "author" => { "login" => expected_author_login },
        "created_at" => created_at,
        "created" => true
      }
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
    cli = SequelAceRelease::CLI.new(
      out: output,
      err: StringIO.new,
      env: {},
      clock: -> { Time.utc(2026, 8, 13) }
    )

    Dir.mktmpdir do |directory|
      body = File.join(directory, "release-body.md")
      File.write(body, "Approved notes")
      status = cli.stub(:github_client, client) do
        cli.stub(:github_user_publisher_client, client) do
          cli.run([
            "github-create-release",
            "--channel", "production",
            "--version", "5.4.0",
            "--build", "20109",
            "--iteration", "1",
            "--target-sha", "a" * 40,
            "--body", body
          ])
        end
      end

      assert_equal 0, status
    end

    assert_equal %i[validate_target validate_publisher create_tag publish_release], client.events
    result = JSON.parse(output.string)
    assert_equal true, result.dig("tag", "created")
    assert_equal 100, result.dig("release", "id")
    assert_equal "Jason-Morcos", result.dig("release", "author", "login")
  end

  def test_cli_switches_initial_release_creation_to_the_app_at_the_fixed_cutoff
    client = Client.new
    output = StringIO.new
    cli = SequelAceRelease::CLI.new(
      out: output,
      err: StringIO.new,
      env: {},
      clock: -> { SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF }
    )

    Dir.mktmpdir do |directory|
      body = File.join(directory, "release-body.md")
      File.write(body, "Approved notes")
      status = cli.stub(:github_client, client) do
        cli.run([
          "github-create-release",
          "--channel", "production",
          "--version", "5.4.0",
          "--build", "20109",
          "--iteration", "1",
          "--target-sha", "a" * 40,
          "--body", body
        ])
      end

      assert_equal 0, status
    end

    assert_equal %i[validate_target validate_app_publisher create_tag publish_release], client.events
    assert_equal SequelAceRelease::ReleasePublisher::RELEASE_APP_LOGIN,
                 JSON.parse(output.string).dig("release", "author", "login")
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
