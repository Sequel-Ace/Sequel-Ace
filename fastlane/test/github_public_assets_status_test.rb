# frozen_string_literal: true

require "test_helper"

class GitHubPublicAssetsStatusTest < Minitest::Test
  BODY = <<~BODY.freeze
    ## App Store Release Notes

    A focused release note.

    ## What's Changed

    - A tested change.
  BODY

  class GitHub
    def initialize(release)
      @release = release
    end

    def ref_sha(_ref)
      "d" * 40
    end

    def release_by_tag(_tag)
      @release
    end

    def public_release_feed_page
      [@release]
    end

    def validate_release_target!(target_sha:, protected_paths:)
      raise "wrong release target" unless target_sha == "d" * 40
      raise "missing protected paths" if protected_paths.empty?

      { "target_sha" => target_sha }
    end
  end

  def test_missing_legacy_asset_returns_a_nonmutating_browser_handoff
    with_handoff(assets: []) do |manifest, notes, _marker, output, client|
      assert_equal 0, run_cli(manifest: manifest, notes: notes, output: output, client: client)
      status = JSON.parse(File.read(output))
      assert_equal false, status.fetch("ready")
      assert_equal "manual_web_upload", status.fetch("mode")
      assert_equal "legacy_updater_v1", status.fetch("compatibility_profile")
      assert_equal ["Sequel-Ace-5.4.0.zip"], status.fetch("missing_assets")
      refute status.key?("release_feed_entries_verified")
    end
  end

  def test_exact_web_uploaded_asset_is_ready
    with_handoff(assets: [asset]) do |manifest, notes, _marker, output, client|
      assert_equal 0, run_cli(manifest: manifest, notes: notes, output: output, client: client)
      status = JSON.parse(File.read(output))
      assert_equal true, status.fetch("ready")
      assert_equal ["Sequel-Ace-5.4.0.zip"], status.fetch("verified_assets")
      assert_equal 1, status.fetch("release_feed_entries_verified")
    end
  end

  def test_incompatible_public_metadata_is_terminal_integrity_evidence
    incompatible = asset.merge("label" => "")
    with_handoff(assets: [incompatible]) do |manifest, notes, marker, output, client|
      assert_equal 1, run_cli(manifest: manifest, notes: notes, marker: marker, output: output, client: client)
      assert_equal "release asset integrity failure\n", File.read(marker)
      refute_path_exists output
    end
  end

  def test_anonymous_rate_limit_is_retryable_and_does_not_write_an_integrity_marker
    with_handoff(assets: [asset]) do |manifest, notes, marker, output, client|
      client.define_singleton_method(:public_release_feed_page) do
        raise SequelAceRelease::APIError, "GitHub API returned HTTP 403: API rate limit exceeded"
      end

      assert_equal 1, run_cli(manifest: manifest, notes: notes, marker: marker, output: output, client: client)
      refute_path_exists marker
      refute_path_exists output
    end
  end

  private

  def run_cli(manifest:, notes:, output:, client:, marker: nil)
    arguments = [
      "github-public-assets-status",
      "--tag", "production/5.4.0-20109",
      "--manifest", manifest,
      "--notes", notes,
      "--output", output
    ]
    arguments += ["--integrity-failure-marker", marker] if marker
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    cli.stub(:github_client, client) { cli.run(arguments) }
  end

  def with_handoff(assets:)
    Dir.mktmpdir do |directory|
      naming = SequelAceRelease::ReleaseNaming.new(
        channel: "production", version: "5.4.0", build: 20_109, iteration: 1
      )
      digest = Digest::SHA256.hexdigest("verified release bytes")
      manifest = SequelAceRelease::Manifest.create(
        approval: approval(
          target_version: "5.4.0",
          release_notes_sha256: Digest::SHA256.hexdigest(BODY)
        ),
        naming: naming,
        base_sha: "b" * 40,
        canonical_build: 20_109,
        production_build_evidence: production_build_evidence(target: 20_109),
        release_notes_sha256: Digest::SHA256.hexdigest(BODY),
        state: "artifacts_verified"
      ).with(
        "release_commit_sha" => "d" * 40,
        "verification" => {
          "production" => {
            "zip_path" => "/private/archive/Sequel-Ace-5.4.0.zip",
            "zip_sha256" => digest
          }
        }
      )
      manifest_path = File.join(directory, "manifest.json")
      notes_path = File.join(directory, "notes.txt")
      marker_path = File.join(directory, "terminal-marker")
      output_path = File.join(directory, "public-assets.json")
      manifest.write(manifest_path)
      File.write(notes_path, "A focused release note.\n")
      release = github_release_payload(
        id: 370_232_757,
        tag: naming.tag,
        title: naming.title,
        body: BODY,
        assets: assets
      )
      yield manifest_path, notes_path, marker_path, output_path, GitHub.new(release)
    end
  end

  def asset
    github_release_asset(
      id: 515_968_456,
      name: "Sequel-Ace-5.4.0.zip",
      digest: Digest::SHA256.hexdigest("verified release bytes")
    )
  end
end
