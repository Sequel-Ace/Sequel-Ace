# frozen_string_literal: true

require "test_helper"
require_relative "../../Scripts/verify-oras-checksums"

class ORASChecksumVerifierTest < Minitest::Test
  def test_current_and_minor_updated_pins_are_verified_without_version_fixtures
    pins = current_inputs
    version = pins.fetch("url").match(%r{/download/v([^/]+)/}).captures.first
    major, minor, = version.split(".").map(&:to_i)
    updated = [major, minor + 1, 0].join(".")
    [pins, pins.merge("url" => pins.fetch("url").gsub(version, updated),
                      "checksum" => Digest::SHA256.hexdigest("updated archive"))].each do |inputs|
      with_workflow(inputs, copies: 2) do |path|
        requests = []
        fetch = lambda do |url|
          requests << url
          assert_equal inputs.fetch("url").sub(/_[^_]+_[^_]+\.tar\.gz\z/, "_checksums.txt"), url
          "#{inputs.fetch('checksum')}  #{File.basename(inputs.fetch('url'))}\n"
        end
        assert_equal 2, verify(path, fetch)
        assert_equal 1, requests.length, "Fetch each release manifest only once"
      end
    end
  end

  def test_consistently_mistyped_checksum_is_rejected
    inputs = current_inputs
    with_workflow(inputs.merge("checksum" => Digest::SHA256.hexdigest("wrong archive")), copies: 2) do |path|
      fetch = ->(_url) { "#{inputs.fetch('checksum')}  #{File.basename(inputs.fetch('url'))}\n" }
      error = assert_raises(RuntimeError) { verify(path, fetch) }
      assert_includes error.message, "checksum does not match upstream manifest"
    end
  end

  def test_missing_or_duplicate_manifest_entries_are_rejected
    inputs = current_inputs
    entry = "#{inputs.fetch('checksum')}  #{File.basename(inputs.fetch('url'))}\n"
    ["", entry + entry].each do |manifest|
      with_workflow(inputs) do |path|
        error = assert_raises(RuntimeError) { verify(path, ->(_url) { manifest }) }
        assert_includes error.message, "checksum does not match upstream manifest"
      end
    end
  end

  def test_manifest_download_failure_is_not_ignored
    with_workflow(current_inputs) do |path|
      assert_raises(IOError) { verify(path, ->(_url) { raise IOError, "upstream unavailable" }) }
    end
  end

  private

  def current_inputs
    workflow = YAML.load_file(File.expand_path("../../.github/workflows/release.yml", __dir__))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
            .find { |step| step["uses"].to_s.start_with?("oras-project/setup-oras@") }.fetch("with")
  end

  def with_workflow(inputs, copies: 1)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "workflow.yml")
      step = { "uses" => "oras-project/setup-oras@#{Digest::SHA1.hexdigest('action')}", "with" => inputs }
      File.write(path, { "jobs" => { "test" => { "steps" => Array.new(copies) { Marshal.load(Marshal.dump(step)) } } } }.to_yaml)
      yield path
    end
  end

  def verify(path, fetch)
    SequelAceRelease::ORASChecksumVerifier.verify(workflow_paths: [path], fetch_manifest: fetch)
  end
end
