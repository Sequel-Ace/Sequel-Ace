# frozen_string_literal: true

require "test_helper"

class CloudArtifactDownloadTest < Minitest::Test
  def test_publisher_downloads_only_the_stapled_artifact
    artifacts = %w[LOG_BUNDLE ARCHIVE_EXPORT STAPLED_NOTARIZED_ARCHIVE].map do |type|
      { "id" => type, "attributes" => {
        "fileType" => type, "fileName" => "#{type}.zip",
        "downloadUrl" => "https://example.invalid/#{type}", "fileSize" => 5
      } }
    end
    client = Object.new
    client.define_singleton_method(:run_artifacts) { |_run| artifacts }
    downloads = []
    runner = Object.new
    runner.define_singleton_method(:run) do |*args, **_options|
      downloads << args.last
      File.write(args[args.index("--output") + 1], "bytes")
    end
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    cli.instance_variable_set(:@runner, runner)

    Dir.mktmpdir do |directory|
      output = File.join(directory, "index.json")
      cli.stub(:app_store_client, client) do
        assert_equal 0, cli.run([
          "download-cloud-artifacts", "--run-id", "run-id", "--notarized-only",
          "--output-directory", directory, "--output", output
        ])
      end
      assert_equal ["https://example.invalid/STAPLED_NOTARIZED_ARCHIVE"], downloads
      index = JSON.parse(File.read(output))
      assert_equal ["STAPLED_NOTARIZED_ARCHIVE"], index.fetch("artifacts").map { |item| item.fetch("file_type") }
    end
  end

  def test_missing_stapled_artifact_stops_before_download_or_verification
    client = Object.new
    client.define_singleton_method(:run_artifacts) do |_run|
      [{ "id" => "export", "attributes" => {
        "fileType" => "ARCHIVE_EXPORT", "downloadUrl" => "https://example.invalid/export.zip"
      } }]
    end
    runner = Object.new
    runner.define_singleton_method(:run) { |*| raise "download must not start" }
    err = StringIO.new
    cli = SequelAceRelease::CLI.new(out: StringIO.new, err: err, env: {})
    cli.instance_variable_set(:@runner, runner)
    Dir.mktmpdir do |directory|
      destination = File.join(directory, "downloads")
      cli.stub(:app_store_client, client) do
        assert_equal 1, cli.run([
          "download-cloud-artifacts", "--run-id", "run-id", "--notarized-only",
          "--output-directory", destination
        ])
      end
      refute_path_exists destination
      assert_includes err.string, "stapled notarized artifact is not ready"
    end
  end
end
