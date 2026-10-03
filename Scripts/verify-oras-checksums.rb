# frozen_string_literal: true

require "yaml"
require "open3"

module SequelAceRelease
  # CI checks the current workflow pins against upstream without version fixtures.
  class ORASChecksumVerifier
    def self.verify(workflow_paths:, fetch_manifest: method(:download_manifest))
      steps = workflow_paths.flat_map do |path|
        YAML.load_file(path).fetch("jobs", {}).values.flat_map { |job| job.fetch("steps", []) }
      end.select { |step| step["uses"].to_s.start_with?("oras-project/setup-oras") }
      raise "No ORAS installations found" if steps.empty?

      manifests = {}
      steps.each do |step|
        inputs = step.fetch("with")
        url = inputs.fetch("url")
        archive = %r{\A(https://github\.com/oras-project/oras/releases/download/v(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?))/(oras_\2_(?:linux_amd64|darwin_arm64|darwin_amd64)\.tar\.gz)\z}.match(url)
        raise "Invalid ORAS archive URL: #{url}" unless archive

        manifest_url = "#{archive[1]}/oras_#{archive[2]}_checksums.txt"
        manifest = manifests[manifest_url] ||= fetch_manifest.call(manifest_url)
        entries = manifest.lines.filter_map do |line|
          match = /\A([0-9a-f]{64})\s+\*?(\S+)\s*\z/.match(line)
          match[1] if match && match[2] == archive[3]
        end
        unless entries.length == 1 && entries.first == inputs.fetch("checksum")
          raise "ORAS checksum does not match upstream manifest for #{archive[3]}"
        end
      end
      steps.length
    end

    def self.download_manifest(url)
      stdout, _stderr, status = Open3.capture3(
        "curl", "--fail", "--silent", "--show-error", "--location",
        "--retry", "3", "--retry-delay", "1", "--connect-timeout", "10", "--max-time", "60",
        "--proto", "=https", "--proto-redir", "=https", url
      )
      raise "Could not fetch ORAS checksum manifest: #{url}" unless status.success?

      stdout
    end
  end
end

if $PROGRAM_NAME == __FILE__
  paths = Dir.glob(File.expand_path("../.github/workflows/*.{yml,yaml}", __dir__))
  count = SequelAceRelease::ORASChecksumVerifier.verify(workflow_paths: paths)
  puts "Verified #{count} ORAS installation checksums against upstream release manifests"
end
