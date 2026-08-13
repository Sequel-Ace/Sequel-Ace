# frozen_string_literal: true

require "test_helper"

class GitHubReleaseCreationTest < Minitest::Test
  class Client
    attr_reader :events

    def initialize(existing_release: nil)
      @events = []
      @existing_release = existing_release
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

    def validate_release_app_publisher!(
      expected_app_id:, expected_client_id:, expected_app_slug:, expected_installation_id:
    )
      raise "wrong release App" unless expected_app_id == SequelAceRelease::ReleasePublisher::RELEASE_APP_ID
      raise "wrong release App client ID" unless expected_client_id == "Iv1.releaseclient"
      unless expected_app_slug == "sequel-ace-release-automation" && expected_installation_id == "12345"
        raise "wrong release App installation"
      end

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

    def release_by_tag_if_exists(tag)
      raise "wrong tag" unless tag == "production/5.4.0-20109"

      @events << :find_release
      @existing_release
    end

    def validate_existing_release(release:, tag:, target_sha:, title:, body:, expected_author_login:)
      raise "wrong existing release" unless release.equal?(@existing_release)
      raise "wrong tag" unless tag == "production/5.4.0-20109"
      raise "wrong target" unless target_sha == "a" * 40
      raise "wrong title" unless title == "5.4.0 (20109) - Release Candidate 1"
      raise "wrong body" unless body == "Approved notes"
      raise "wrong release author" unless expected_author_login == release.dig("author", "login")

      @events << :validate_existing_release
      release.merge("created" => false)
    end

    def create_or_validate_release(tag:, target_sha:, title:, body:, expected_author_login:)
      expected_events = if expected_author_login == SequelAceRelease::ReleasePublisher::USER_LOGIN
                          %i[validate_target find_release validate_publisher create_tag]
                        else
                          %i[validate_target find_release validate_app_publisher create_tag]
                        end
      raise "release preflight order changed" unless @events == expected_events
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
      unless %w[production/5.4.0-20105 production/5.4.0-20109].include?(tag)
        raise "wrong tag"
      end
      raise "wrong target" unless target_sha == "a" * 40

      @events << (tag.end_with?("-20109") ? :validate_tag : :verify_tag)
      {
        "ref" => "refs/tags/#{tag}",
        "object" => { "type" => "commit", "sha" => target_sha },
        "created" => false
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

    assert_equal %i[validate_target find_release validate_publisher create_tag publish_release], client.events
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
      env: {
        "SA_RELEASE_GITHUB_APP_CLIENT_ID" => "Iv1.releaseclient",
        "SA_RELEASE_GITHUB_APP_SLUG" => "sequel-ace-release-automation",
        "SA_RELEASE_GITHUB_APP_INSTALLATION_ID" => "12345"
      },
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

    assert_equal %i[validate_target find_release validate_app_publisher create_tag publish_release], client.events
    assert_equal SequelAceRelease::ReleasePublisher::RELEASE_APP_LOGIN,
                 JSON.parse(output.string).dig("release", "author", "login")
  end

  def test_cli_recovers_a_pre_cutoff_user_release_after_the_cutoff_without_the_pat
    existing = {
      "id" => 100,
      "tag_name" => "production/5.4.0-20109",
      "name" => "5.4.0 (20109) - Release Candidate 1",
      "body" => "Approved notes",
      "draft" => false,
      "prerelease" => true,
      "author" => { "login" => SequelAceRelease::ReleasePublisher::USER_LOGIN },
      "created_at" => "2027-08-13T23:00:00Z"
    }
    client = Client.new(existing_release: existing)
    output = StringIO.new
    cli = SequelAceRelease::CLI.new(
      out: output,
      err: StringIO.new,
      env: {},
      clock: -> { SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF + 60 }
    )

    Dir.mktmpdir do |directory|
      body = File.join(directory, "release-body.md")
      File.write(body, "Approved notes")
      status = cli.stub(:github_client, client) do
        cli.stub(:github_user_publisher_client, -> { raise "publisher PAT must not be loaded" }) do
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

    assert_equal %i[validate_target find_release validate_tag validate_existing_release], client.events
    result = JSON.parse(output.string)
    assert_equal "existing", result.dig("publisher_validation", "mode")
    assert_equal "Jason-Morcos", result.dig("release", "author", "login")
  end

  def test_publisher_mode_recovers_an_existing_release_during_the_safety_window
    existing = {
      "id" => 100,
      "author" => { "login" => SequelAceRelease::ReleasePublisher::USER_LOGIN },
      "created_at" => "2027-08-13T23:00:00Z"
    }
    client = Client.new(existing_release: existing)
    output = StringIO.new
    cutoff = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF
    cli = SequelAceRelease::CLI.new(
      out: output,
      err: StringIO.new,
      env: {},
      clock: -> { cutoff - 1 }
    )

    status = cli.stub(:github_client, client) do
      cli.run(["github-release-publisher-mode", "--tag", "production/5.4.0-20109"])
    end

    assert_equal 0, status
    assert_equal "existing", JSON.parse(output.string).fetch("mode")
    assert_equal 100, JSON.parse(output.string).fetch("existing_release_id")
  end

  def test_publisher_mode_blocks_a_fresh_release_during_the_safety_window
    client = Client.new
    error = StringIO.new
    cutoff = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF
    cli = SequelAceRelease::CLI.new(
      out: StringIO.new,
      err: error,
      env: {},
      clock: -> { cutoff - 1 }
    )

    status = cli.stub(:github_client, client) do
      cli.run(["github-release-publisher-mode", "--tag", "production/5.4.0-20109"])
    end

    assert_equal 1, status
    assert_includes error.string, "cutoff safety window"
  end

  def test_create_release_blocks_the_safety_window_before_loading_the_pat_or_creating_the_tag
    client = Client.new
    error = StringIO.new
    cutoff = SequelAceRelease::ReleasePublisher::USER_PUBLISHER_CUTOFF
    cli = SequelAceRelease::CLI.new(
      out: StringIO.new,
      err: error,
      env: {},
      clock: -> { cutoff - 1 }
    )

    Dir.mktmpdir do |directory|
      body = File.join(directory, "release-body.md")
      File.write(body, "Approved notes")
      status = cli.stub(:github_client, client) do
        cli.stub(:github_user_publisher_client, -> { raise "publisher PAT must not be loaded" }) do
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

      assert_equal 1, status
    end

    assert_equal %i[validate_target find_release], client.events
    assert_includes error.string, "cutoff safety window"
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
