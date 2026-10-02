# frozen_string_literal: true

require "test_helper"

class PublicHandoffTest < Minitest::Test
  include ReleaseTestHelpers

  def with_archive
    Dir.mktmpdir do |root|
      archive = File.join(root, "archive")
      destination = File.join(root, "public")
      FileUtils.mkdir_p(File.join(archive, "artifacts", "public"))
      name = "Sequel-Ace-5.3.2.zip"
      zip = File.join(archive, "artifacts", "public", name)
      File.binwrite(zip, "verified ZIP fixture")
      File.write(File.join(archive, "private-evidence.json"), "NEVER PUBLISH")
      naming = SequelAceRelease::ReleaseNaming.new(channel: "production", version: "5.3.2", build: 20_105, iteration: 1)
      manifest = SequelAceRelease::Manifest.create(
        approval: approval, naming: naming, base_sha: "b" * 40,
        canonical_build: 20_105, production_build_evidence: production_build_evidence,
        release_notes_sha256: "c" * 64, state: "artifacts_verified"
      ).with("verification" => { "production" => { "zip_path" => "artifacts/public/#{name}", "zip_sha256" => Digest::SHA256.file(zip).hexdigest } })
      manifest.write(File.join(archive, "manifest.json"))
      yield archive, destination, zip, manifest
    end
  end

  def run_handoff(archive, destination)
    output, error = StringIO.new, StringIO.new
    result = SequelAceRelease::CLI.run(["stage-public-handoff", "--archive", archive, "--destination", destination], out: output, err: error, env: {})
    [result, output.string, error.string]
  end

  def test_only_copies_named_public_zip_and_checksums_never_private_evidence
    with_archive do |archive, destination, zip, _manifest|
      result, output, error = run_handoff(archive, destination)
      assert_equal 0, result, error
      assert_equal ["SHA256SUMS.txt", File.basename(zip)].sort, Dir.children(destination).sort
      assert_equal File.binread(zip), File.binread(File.join(destination, File.basename(zip)))
      assert_includes File.read(File.join(destination, "SHA256SUMS.txt")), Digest::SHA256.file(zip).hexdigest
      refute_includes output, "NEVER PUBLISH"
    end
  end

  def test_corrupt_bytes_do_not_create_a_public_bundle
    with_archive do |archive, destination, zip, _manifest|
      File.binwrite(zip, "wrong bytes")
      result, _, error = run_handoff(archive, destination)
      assert_equal 1, result
      assert_includes error, "manifest checksum"
      refute File.exist?(destination)
    end
  end

  def test_unverified_state_does_not_create_a_public_bundle
    with_archive do |archive, destination, _zip, manifest|
      manifest.with("state" => "cloud_running").write(File.join(archive, "manifest.json"))
      result, _, error = run_handoff(archive, destination)
      assert_equal 1, result
      assert_includes error, "requires verified artifacts"
      refute File.exist?(destination)
    end
  end

  def test_symlink_cannot_export_even_a_matching_file
    with_archive do |archive, destination, zip, _manifest|
      moved = File.join(archive, "same-bytes.zip")
      FileUtils.mv(zip, moved)
      File.symlink(moved, zip)
      result, _, error = run_handoff(archive, destination)
      assert_equal 1, result
      assert_includes error, "non-symlink"
      refute File.exist?(destination)
    end
  end

  def test_does_not_overwrite_an_existing_destination
    with_archive do |archive, destination, _zip, _manifest|
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, "sentinel"), "keep")
      assert_equal 1, run_handoff(archive, destination).first
      assert_equal "keep", File.read(File.join(destination, "sentinel"))
    end
  end
end
