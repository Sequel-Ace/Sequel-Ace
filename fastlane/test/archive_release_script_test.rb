# frozen_string_literal: true

require "test_helper"
require "open3"

class ArchiveReleaseScriptTest < Minitest::Test
  def test_push_gives_oras_only_relative_layer_paths_and_verifies_the_pull
    Dir.mktmpdir do |directory|
      archive = File.join(directory, "archive")
      binary_directory = File.join(directory, "bin")
      remote = File.join(directory, "remote")
      arguments_file = File.join(directory, "push-arguments.txt")
      FileUtils.mkdir_p([archive, binary_directory, remote])
      File.write(File.join(archive, "manifest.json"), "{\"schema_version\":1}\n")
      File.write(File.join(archive, "evidence.txt"), "verified\n")
      fake_oras = File.join(binary_directory, "oras")
      File.write(fake_oras, fake_oras_script)
      FileUtils.chmod(0o755, fake_oras)
      fake_mktemp = File.join(binary_directory, "mktemp")
      File.write(fake_mktemp, <<~'BASH')
        #!/usr/bin/env bash
        set -euo pipefail
        [[ "${1:-}" == "-d" ]]
        [[ "${2:-}" != "-t" ]]
        exec /usr/bin/mktemp "$@"
      BASH
      FileUtils.chmod(0o755, fake_mktemp)

      stdout, stderr, status = Open3.capture3(
        {
          "PATH" => "#{binary_directory}:#{ENV.fetch('PATH')}",
          "GHCR_TOKEN" => "test-token",
          "GHCR_USERNAME" => "test-user",
          "ORAS_REMOTE_DIRECTORY" => remote,
          "ORAS_ARGUMENTS_FILE" => arguments_file
        },
        "/bin/bash",
        repo_path("Scripts/archive-release-to-ghcr.sh"),
        "push",
        "ghcr.io/sequel-ace/sequel-ace-release-archive:test",
        archive
      )

      assert status.success?, stderr
      evidence = JSON.parse(stdout)
      assert_match(/\A[0-9a-f]{64}\z/, evidence.fetch("archive_sha256"))
      assert_match(/\A[0-9a-f]{64}\z/, evidence.fetch("manifest_sha256"))
      arguments = File.readlines(arguments_file, chomp: true)
      assert_equal 2, arguments.length
      arguments.each do |argument|
        path = argument.split(":", 2).first
        refute path.start_with?("/"), "ORAS layer path must be relative: #{path}"
      end
    end
  end

  def test_pull_rejects_a_nonempty_destination_before_downloading
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      FileUtils.mkdir_p([remote, destination])
      File.write(File.join(destination, "sentinel"), "keep\n")

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "GHCR destination must be empty"
      assert_equal "keep\n", File.read(File.join(destination, "sentinel"))
    end
  end

  def test_pull_uses_an_explicit_temporary_registry_config_for_login_and_pull
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      registry_config = File.join(directory, "oras", "registry.json")
      arguments_file = File.join(directory, "arguments.txt")
      FileUtils.mkdir_p([remote, File.dirname(registry_config)])
      build_remote_archive(remote)

      _stdout, stderr, status = run_pull(
        remote: remote,
        destination: destination,
        extra_environment: {
          "GHCR_REGISTRY_CONFIG" => registry_config,
          "ORAS_ARGUMENTS_FILE" => arguments_file
        }
      )

      assert status.success?, stderr
      registry_configs = File.readlines(arguments_file, chomp: true)
      assert_equal [registry_config, registry_config], registry_configs
    end
  end

  def test_pull_rejects_parent_traversal_before_tar_can_touch_the_parent
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      victim = File.join(directory, "preflight-victim.txt")
      File.write(victim, "safe\n")
      build_raw_remote_archive(
        remote,
        raw_file("manifest.json", "{\"schema_version\":1}\n"),
        raw_file("../preflight-victim.txt", "unsafe\n")
      )

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "member path contains '..'"
      assert_equal "safe\n", File.read(victim)
    end
  end

  def test_pull_rejects_a_symlink_pivot_before_tar_can_follow_it
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      outside = File.join(directory, "outside")
      FileUtils.mkdir_p(outside)
      build_raw_remote_archive(
        remote,
        raw_file("manifest.json", "{\"schema_version\":1}\n"),
        raw_directory("artifacts"),
        raw_symlink("artifacts/pivot", "../../outside"),
        raw_file("artifacts/pivot/payload.txt", "unsafe\n")
      )

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "escaping artifact symlink"
      refute File.exist?(File.join(outside, "payload.txt"))
    end
  end

  def test_pull_rejects_a_top_level_symlink
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      victim = File.join(directory, "victim.rb")
      File.write(victim, "safe\n")
      build_remote_archive(remote) do |source|
        File.symlink(victim, File.join(source, "context.json"))
      end

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "symlink outside artifacts/"
      assert_equal "safe\n", File.read(victim)
    end
  end

  def test_pull_rejects_an_artifact_symlink_that_escapes_the_archive
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      victim = File.join(directory, "victim.txt")
      File.write(victim, "outside\n")
      build_remote_archive(remote) do |source|
        FileUtils.mkdir_p(File.join(source, "artifacts"))
        File.symlink("../../victim.txt", File.join(source, "artifacts", "escape"))
      end

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "escaping artifact symlink"
    end
  end

  def test_pull_rejects_an_absolute_artifact_symlink
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      victim = File.join(directory, "victim.txt")
      File.write(victim, "outside\n")
      build_remote_archive(remote) do |source|
        FileUtils.mkdir_p(File.join(source, "artifacts"))
        File.symlink(victim, File.join(source, "artifacts", "absolute"))
      end

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "unsafe artifact symlink target"
    end
  end

  def test_pull_accepts_an_internal_artifact_symlink
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      build_remote_archive(remote) do |source|
        version = File.join(source, "artifacts", "Versions", "A")
        FileUtils.mkdir_p(version)
        File.write(File.join(version, "binary"), "verified\n")
        File.symlink("A", File.join(source, "artifacts", "Versions", "Current"))
      end

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      assert status.success?, stderr
      manifest = File.join(destination, "manifest.json")
      current = File.join(destination, "artifacts", "Versions", "Current")
      assert File.file?(manifest)
      refute File.symlink?(manifest)
      assert File.symlink?(current)
      assert_equal File.realpath(File.join(destination, "artifacts", "Versions", "A")), File.realpath(current)
    end
  end

  def test_pull_rejects_a_hard_link_to_a_control_file
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      build_remote_archive(remote) do |source|
        File.link(
          File.join(source, "manifest.json"),
          File.join(source, "finalization-validation.json")
        )
      end

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "hard link outside artifacts/"
    end
  end

  def test_pull_accepts_a_fully_contained_artifact_hard_link
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      build_remote_archive(remote) do |source|
        artifacts = File.join(source, "artifacts")
        FileUtils.mkdir_p(artifacts)
        original = File.join(artifacts, "binary")
        File.write(original, "verified\n")
        File.link(original, File.join(artifacts, "binary-copy"))
      end

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      assert status.success?, stderr
      original = File.stat(File.join(destination, "artifacts", "binary"))
      copy = File.stat(File.join(destination, "artifacts", "binary-copy"))
      assert_equal [original.dev, original.ino], [copy.dev, copy.ino]
    end
  end

  def test_pull_rejects_an_archive_manifest_that_differs_from_the_oci_layer
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      build_remote_archive(remote)
      File.write(File.join(remote, "manifest.json"), "{\"schema_version\":2}\n")

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "manifest does not match its manifest layer"
    end
  end

  def test_pull_rejects_an_unexpected_oci_layer
    Dir.mktmpdir do |directory|
      remote = File.join(directory, "remote")
      destination = File.join(directory, "destination")
      build_remote_archive(remote)
      File.write(File.join(remote, "context.json"), "{}\n")

      _stdout, stderr, status = run_pull(remote: remote, destination: destination)

      refute status.success?
      assert_includes stderr, "unexpected top-level layer"
    end
  end

  private

  def repo_path(relative_path)
    File.expand_path("../..", __dir__) + "/#{relative_path}"
  end

  def build_remote_archive(remote)
    source = "#{remote}-source"
    FileUtils.mkdir_p([remote, source])
    manifest = "{\"schema_version\":1}\n"
    File.write(File.join(source, "manifest.json"), manifest)
    yield source if block_given?
    assert system("/usr/bin/tar", "-czf", File.join(remote, "sequel-ace-release-archive.tar.gz"), "-C", source, ".")
    File.write(File.join(remote, "manifest.json"), manifest)
  end

  def build_raw_remote_archive(remote, *entries)
    FileUtils.mkdir_p(remote)
    archive = File.join(remote, "sequel-ace-release-archive.tar.gz")
    Zlib::GzipWriter.open(archive) do |gzip|
      entries.each do |entry|
        data = entry.fetch(:data)
        header = Gem::Package::TarHeader.new(
          name: entry.fetch(:name),
          prefix: "",
          mode: entry.fetch(:mode, 0o644),
          size: data.bytesize,
          typeflag: entry.fetch(:typeflag),
          linkname: entry.fetch(:linkname, "")
        )
        gzip.write(header.to_s)
        gzip.write(data)
        gzip.write("\0" * ((512 - (data.bytesize % 512)) % 512))
      end
      gzip.write("\0" * 1_024)
    end
    File.write(File.join(remote, "manifest.json"), "{\"schema_version\":1}\n")
  end

  def raw_file(name, data)
    { name: name, typeflag: "0", data: data }
  end

  def raw_directory(name)
    { name: name, typeflag: "5", data: "", mode: 0o755 }
  end

  def raw_symlink(name, target)
    { name: name, typeflag: "2", data: "", linkname: target, mode: 0o777 }
  end

  def run_pull(remote:, destination:, extra_environment: {})
    binary_directory = File.join(File.dirname(remote), "bin")
    FileUtils.mkdir_p(binary_directory)
    fake_oras = File.join(binary_directory, "oras")
    File.write(fake_oras, fake_oras_script)
    FileUtils.chmod(0o755, fake_oras)

    Open3.capture3(
      {
        "PATH" => "#{binary_directory}:#{ENV.fetch('PATH')}",
        "GHCR_TOKEN" => "test-token",
        "GHCR_USERNAME" => "test-user",
        "ORAS_REMOTE_DIRECTORY" => remote,
        "ORAS_ARGUMENTS_FILE" => File.join(File.dirname(remote), "arguments.txt")
      }.merge(extra_environment),
      "/bin/bash",
      repo_path("Scripts/archive-release-to-ghcr.sh"),
      "pull",
      "ghcr.io/sequel-ace/sequel-ace-release-archive:test",
      destination
    )
  end

  def fake_oras_script
    <<~'BASH'
      #!/usr/bin/env bash
      set -euo pipefail
      command_name="${1}"
      shift
      case "${command_name}" in
        login)
          while [[ "$#" -gt 0 ]]; do
            if [[ "${1}" == "--registry-config" ]]; then
              printf '%s\n' "${2}" >> "${ORAS_ARGUMENTS_FILE}"
              shift 2
            else
              shift
            fi
          done
          cat >/dev/null
          ;;
        push)
          reference="${1}"
          shift
          : > "${ORAS_ARGUMENTS_FILE}"
          for layer in "$@"; do
            path="${layer%%:*}"
            [[ "${path}" != /* ]]
            [[ -f "${path}" ]]
            printf '%s\n' "${layer}" >> "${ORAS_ARGUMENTS_FILE}"
            cp "${path}" "${ORAS_REMOTE_DIRECTORY}/$(basename "${path}")"
          done
          ;;
        pull)
          reference="${1}"
          shift
          output=""
          while [[ "$#" -gt 0 ]]; do
            if [[ "${1}" == "--output" ]]; then
              output="${2}"
              shift 2
            elif [[ "${1}" == "--registry-config" ]]; then
              printf '%s\n' "${2}" >> "${ORAS_ARGUMENTS_FILE}"
              shift 2
            else
              shift
            fi
          done
          [[ -n "${output}" ]]
          mkdir -p "${output}"
          for path in "${ORAS_REMOTE_DIRECTORY}"/*; do
            cp "${path}" "${output}/"
          done
          ;;
        *)
          exit 64
          ;;
      esac
    BASH
  end
end
