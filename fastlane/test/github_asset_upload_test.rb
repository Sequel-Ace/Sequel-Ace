# frozen_string_literal: true

require "test_helper"

class GitHubAssetUploadTest < Minitest::Test
  class Client
    attr_reader :upload_arguments

    def initialize(error, release:, release_commit:)
      @error = error
      @release = release
      @release_commit = release_commit
    end

    def release_by_tag(_tag)
      @release
    end

    def ref_sha(_ref)
      @release_commit
    end

    def validate_release_target!(target_sha:, protected_paths:)
      raise "wrong release commit" unless target_sha == @release_commit
      raise "missing protected paths" if protected_paths.empty?

      { "target_sha" => target_sha }
    end

    def upload_release_asset(**arguments)
      @upload_arguments = arguments
      raise @error if @error

      {
        "id" => 200,
        "name" => arguments.fetch(:name),
        "digest" => "sha256:#{arguments.fetch(:expected_sha256)}"
      }
    end
  end

  def test_marks_only_an_asset_integrity_conflict_as_terminal
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      marker = File.join(directory, "terminal-marker")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

      client = Client.new(
        SequelAceRelease::IntegrityError.new("checksum mismatch"),
        release: release_data,
        release_commit: release_commit
      )
      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, marker, manifest_path, notes_path))
      end

      assert_equal 1, status
      assert_equal "release asset checksum mismatch\n", File.read(marker)
    end
  end

  def test_creates_the_integrity_marker_parent_directory
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      marker = File.join(directory, "nested", "terminal-marker")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      client = Client.new(
        SequelAceRelease::IntegrityError.new("checksum mismatch"),
        release: release_data,
        release_commit: release_commit
      )

      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, marker, manifest_path, notes_path))
      end

      assert_equal 1, status
      assert_equal "release asset checksum mismatch\n", File.read(marker)
    end
  end

  def test_marker_write_failure_does_not_replace_the_integrity_error
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      marker_parent = File.join(directory, "not-a-directory")
      marker = File.join(marker_parent, "terminal-marker")
      File.binwrite(asset, "verified bytes")
      File.write(marker_parent, "blocking file\n")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      error = StringIO.new
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: error, env: {})
      client = Client.new(
        SequelAceRelease::IntegrityError.new("checksum mismatch"),
        release: release_data,
        release_commit: release_commit
      )

      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, marker, manifest_path, notes_path))
      end

      assert_equal 1, status
      assert_includes error.string, "could not write integrity failure marker"
      assert_includes error.string, "checksum mismatch"
    end
  end

  def test_does_not_mark_a_transient_upload_api_failure_as_terminal
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      marker = File.join(directory, "terminal-marker")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})

      client = Client.new(
        SequelAceRelease::APIError.new("HTTP 503"),
        release: release_data,
        release_commit: release_commit
      )
      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, marker, manifest_path, notes_path))
      end

      assert_equal 1, status
      refute_path_exists marker
    end
  end

  def test_passes_the_manifest_approved_checksum_to_the_upload_boundary
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      client = Client.new(nil, release: release_data, release_commit: release_commit)

      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, nil, manifest_path, notes_path))
      end

      assert_equal 0, status
      assert_equal Digest::SHA256.file(asset).hexdigest,
                   client.upload_arguments.fetch(:expected_sha256)
    end
  end

  def test_rejects_bytes_that_differ_from_the_manifest_before_upload
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      marker = File.join(directory, "terminal-marker")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      File.binwrite(asset, "substituted bytes")
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      client = Client.new(nil, release: release_data, release_commit: release_commit)

      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, marker, manifest_path, notes_path))
      end

      assert_equal 1, status
      assert_nil client.upload_arguments
      assert_equal "release asset checksum mismatch\n", File.read(marker)
    end
  end

  def test_missing_asset_is_not_misreported_as_a_checksum_conflict
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      marker = File.join(directory, "terminal-marker")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      File.delete(asset)
      error = StringIO.new
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: error, env: {})
      client = Client.new(nil, release: release_data, release_commit: release_commit)

      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(asset, marker, manifest_path, notes_path))
      end

      assert_equal 1, status
      assert_includes error.string, "not readable: Errno::ENOENT"
      refute_path_exists marker
      assert_nil client.upload_arguments
    end
  end

  def test_rejects_a_noncanonical_requested_asset_name
    Dir.mktmpdir do |directory|
      asset = File.join(directory, "Sequel-Ace-5.3.2.zip")
      File.binwrite(asset, "verified bytes")
      manifest_path, notes_path, release_data, release_commit = write_handoff(directory)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      client = Client.new(nil, release: release_data, release_commit: release_commit)
      arguments = upload_arguments(asset, nil, manifest_path, notes_path) + ["--name", "different.zip"]

      status = cli.stub(:github_client, client) { cli.run(arguments) }

      assert_equal 1, status
      assert_nil client.upload_arguments
    end
  end

  def test_rejects_a_symlinked_asset_before_upload
    Dir.mktmpdir do |directory|
      approved_directory = File.join(directory, "approved")
      supplied_directory = File.join(directory, "supplied")
      FileUtils.mkdir_p([approved_directory, supplied_directory])
      approved = File.join(approved_directory, "Sequel-Ace-5.3.2.zip")
      supplied = File.join(supplied_directory, "Sequel-Ace-5.3.2.zip")
      File.binwrite(approved, "verified bytes")
      File.symlink(approved, supplied)
      manifest_path, notes_path, release_data, release_commit = write_handoff(
        directory,
        verification_path: approved
      )
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      client = Client.new(nil, release: release_data, release_commit: release_commit)

      status = cli.stub(:github_client, client) do
        cli.run(upload_arguments(supplied, nil, manifest_path, notes_path))
      end

      assert_equal 1, status
      assert_nil client.upload_arguments
    end
  end

  private

  def upload_arguments(asset, marker, manifest, notes)
    arguments = [
      "github-upload-asset",
      "--tag", "production/5.3.2-20109",
      "--file", asset,
      "--manifest", manifest,
      "--notes", notes
    ]
    arguments += ["--integrity-failure-marker", marker] if marker
    arguments
  end

  def write_handoff(directory, verification_path: nil)
    body = <<~BODY
      ## App Store Release Notes

      A focused release note.

      ## What's Changed

      - A tested change.
    BODY
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_109, iteration: 1
    )
    verification_path ||= File.join(directory, naming.public_artifacts.fetch(0))
    manifest = SequelAceRelease::Manifest.create(
      approval: approval(release_notes_sha256: Digest::SHA256.hexdigest(body)),
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_109,
      production_build_evidence: production_build_evidence(target: 20_109),
      release_notes_sha256: Digest::SHA256.hexdigest(body),
      state: "artifacts_verified"
    ).with(
      "release_commit_sha" => "d" * 40,
      "verification" => {
        "production" => {
          "zip_path" => verification_path,
          "zip_sha256" => Digest::SHA256.file(verification_path).hexdigest
        }
      }
    )
    manifest_path = File.join(directory, "manifest.json")
    notes_path = File.join(directory, "notes.txt")
    manifest.write(manifest_path)
    File.write(notes_path, "A focused release note.\n")
    release = {
      "id" => 123,
      "tag_name" => naming.tag,
      "name" => naming.title,
      "draft" => false,
      "prerelease" => true,
      "body" => body,
      "author" => {
        "login" => SequelAceRelease::ReleasePublisher::USER_LOGIN,
        "id" => SequelAceRelease::ReleasePublisher::USER_ID
      },
      "created_at" => "2026-08-13T00:00:00Z",
      "assets" => []
    }
    [manifest_path, notes_path, release, "d" * 40]
  end
end
