# frozen_string_literal: true

require "test_helper"

class SubmissionProvenanceTest < Minitest::Test
  BODY = <<~BODY.freeze
    ## App Store Release Notes

    A focused release note.

    ## What's Changed

    - A tested change.
  BODY
  NOTES = "A focused release note."

  class GitHub
    attr_accessor :release

    def initialize(release:, commit:)
      @release = release
      @commit = commit
    end

    def ref_sha(_ref)
      @commit
    end

    def release_by_tag(_tag)
      @release
    end

    def validate_release_target!(target_sha:, protected_paths:)
      raise "wrong target" unless target_sha == @commit
      raise "missing protected paths" if protected_paths.empty?

      { "target_sha" => target_sha }
    end
  end

  def test_live_github_state_is_revalidated_for_an_archived_submission
    manifest = archived_manifest
    github = GitHub.new(release: release_for(manifest), commit: "d" * 40)
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

    cli.stub(:github_client, github) do
      result = cli.send(:validate_submission_handoff!, manifest: manifest, notes: NOTES)
      assert_equal "archived", result.fetch("state")

      github.release = github.release.merge("draft" => true)
      error = assert_raises(SequelAceRelease::ValidationError) do
        cli.send(:validate_submission_handoff!, manifest: manifest, notes: NOTES)
      end
      assert_includes error.message, "draft"
    end
  end

  def test_submit_revalidates_immediately_before_each_apple_mutation
    events = []
    snapshot = metadata_snapshot(build: 20_109, state: "WAITING_FOR_REVIEW", phased_state: "INACTIVE")
    snapshot["version"]["attributes"]["earliestReleaseDate"] = (Time.now + (4 * 24 * 60 * 60)).utc.iso8601
    app_store = Object.new
    app_store.define_singleton_method(:latest_released_version) do |app_id:|
      raise "wrong app" unless app_id == SequelAceRelease::Config::PRODUCTION_APP_ID

      { "id" => "previous-version-id" }
    end
    app_store.define_singleton_method(:localization) do |version_id:|
      raise "wrong prior version" unless version_id == "previous-version-id"

      { "attributes" => { "promotionalText" => "A native database client." } }
    end
    app_store.define_singleton_method(:find_build) do |app_id:, version:, build:|
      raise "wrong exact build" unless app_id == SequelAceRelease::Config::PRODUCTION_APP_ID &&
                                       version == "5.3.2" && build == 20_109

      { "id" => "build-id" }
    end
    app_store.define_singleton_method(:attach_build) do |version_id:, build_id:|
      raise "wrong attachment" unless version_id == "version-id" && build_id == "build-id"

      events << :attach
    end

    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      notes_path = File.join(directory, "notes.txt")
      archived_manifest.write(manifest_path)
      File.write(notes_path, "#{NOTES}\n")
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

      status = cli.stub(:app_store_client, app_store) do
        cli.stub(:validate_submission_handoff!, ->(**_options) { events << :validate }) do
          cli.stub(:fastlane_release_stage, ->(**_options) { events << :stage }) do
            cli.stub(:wait_for_metadata, snapshot) do
              cli.stub(:wait_for_selected_build, snapshot) do
                cli.stub(:fastlane_release_submit, ->(**_options) { events << :submit }) do
                  cli.stub(:wait_for_submission_state, snapshot) do
                    cli.run([
                      "submit",
                      "--manifest", manifest_path,
                      "--notes", notes_path,
                      "--confirm", "SUBMIT 5.3.2 (20109)"
                    ])
                  end
                end
              end
            end
          end
        end
      end

      assert_equal 0, status
      assert_equal %i[validate stage validate attach validate submit], events
    end
  end

  private

  def archived_manifest
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_109, iteration: 1
    )
    SequelAceRelease::Manifest.create(
      approval: approval(release_notes_sha256: Digest::SHA256.hexdigest(BODY)),
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_109,
      production_build_evidence: production_build_evidence(target: 20_109),
      release_notes_sha256: Digest::SHA256.hexdigest(BODY),
      state: "archived"
    ).with(
      "release_commit_sha" => "d" * 40,
      "verification" => {
        "production" => {
          "zip_path" => "/tmp/Sequel-Ace-5.3.2.zip",
          "zip_sha256" => "e" * 64
        }
      }
    )
  end

  def release_for(manifest)
    {
      "id" => 100,
      "tag_name" => manifest.to_h.fetch("tag"),
      "name" => manifest.to_h.fetch("title"),
      "draft" => false,
      "prerelease" => true,
      "body" => BODY,
      "author" => legacy_author,
      "created_at" => "2026-08-13T00:00:00Z",
      "assets" => [{
        "name" => "Sequel-Ace-5.3.2.zip",
        "digest" => "sha256:#{'e' * 64}",
        "content_type" => "application/zip",
        "state" => "uploaded",
        "label" => nil,
        "uploader" => legacy_author
      }]
    }
  end

  def legacy_author
    SequelAceRelease::LegacyReleasePayload::JASON_IDENTITY.merge(
      "login" => SequelAceRelease::ReleasePublisher::USER_LOGIN
    )
  end
end
