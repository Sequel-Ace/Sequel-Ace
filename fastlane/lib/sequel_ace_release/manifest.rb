# frozen_string_literal: true

require "time"

module SequelAceRelease
  class Manifest
    REQUIRED = %w[
      schema_version channel target_version base_tag base_sha
      changelog_base_tag changelog_base_sha main_sha iteration
      observed_production_cloud_next_build canonical_build skipped_production_builds tag title artifact_names
      release_notes_sha256 cloud_build_ids asc_ids verification state
    ].freeze

    attr_reader :data

    def initialize(data)
      @data = CanonicalJSON.sort(data)
      validate!
    end

    def self.create(approval:, naming:, base_sha:, canonical_build:, skipped_production_builds: [], release_notes_sha256:, state: "planned")
      approved_base_sha = approval.payload.fetch("base_sha")
      unless base_sha == approved_base_sha
        raise ValidationError, "release base SHA does not match the immutable approval"
      end
      approved_release_notes_sha256 = approval.payload.fetch("release_notes_sha256")
      unless release_notes_sha256 == approved_release_notes_sha256
        raise ValidationError, "GitHub release body does not match the immutable approval"
      end
      approved_iteration = approval.payload.fetch("release_iteration")
      unless naming.iteration == approved_iteration
        raise ValidationError, "release iteration does not match the immutable approval"
      end

      new(
        "schema_version" => Config::SCHEMA_VERSION,
        "channel" => approval.payload.fetch("channel"),
        "target_version" => approval.payload.fetch("target_version"),
        "base_tag" => approval.payload.fetch("previous_tag"),
        "base_sha" => approved_base_sha,
        "changelog_base_tag" => approval.payload.fetch("changelog_base_tag"),
        "changelog_base_sha" => approval.payload.fetch("changelog_base_sha"),
        "main_sha" => approval.payload.fetch("main_sha"),
        "iteration" => approved_iteration,
        "observed_production_cloud_next_build" => approval.payload.fetch("observed_production_cloud_next_build"),
        "canonical_build" => canonical_build,
        "skipped_production_builds" => skipped_production_builds,
        "tag" => naming.tag,
        "title" => naming.title,
        "artifact_names" => naming.public_artifacts,
        "release_notes_sha256" => approved_release_notes_sha256,
        "cloud_build_ids" => {},
        "asc_ids" => {},
        "verification" => {},
        "state" => state,
        "created_at" => Time.now.utc.iso8601
      )
    end

    def self.read(path)
      new(JSON.parse(File.read(path)))
    rescue JSON::ParserError => e
      raise ValidationError, "invalid manifest JSON: #{e.message}"
    end

    def with(updates)
      self.class.new(data.merge(CanonicalJSON.sort(updates)))
    end

    def write(path)
      File.write(path, CanonicalJSON.pretty(data))
    end

    def to_h
      data
    end

    private

    def validate!
      missing = REQUIRED - data.keys
      raise ValidationError, "manifest is missing: #{missing.join(', ')}" unless missing.empty?
      raise ValidationError, "unsupported manifest schema" unless data["schema_version"] == Config::SCHEMA_VERSION

      Config.validate_channel!(data["channel"])
      Version.validate!(data["target_version"])
      %w[base_tag changelog_base_tag].each do |key|
        unless data[key].to_s.match?(%r{\A(?:production|beta)/\d+\.\d+\.\d+-\d+\z})
          raise ValidationError, "#{key.tr('_', ' ')} is malformed"
        end
      end
      %w[base_sha changelog_base_sha main_sha].each do |key|
        unless data[key].to_s.match?(/\A[0-9a-f]{40,64}\z/i)
          raise ValidationError, "#{key.tr('_', ' ')} is malformed"
        end
      end
      raise ValidationError, "invalid manifest state" unless Config::MANIFEST_STATES.include?(data["state"])
      validate_positive_integer!(data["canonical_build"], "canonical build")
      validate_positive_integer!(data["iteration"], "release iteration")
      unless data["release_notes_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
        raise ValidationError, "release notes SHA-256 is malformed"
      end
      if data.key?("release_commit_sha") && !data["release_commit_sha"].to_s.match?(/\A[0-9a-f]{40,64}\z/i)
        raise ValidationError, "release commit SHA is malformed"
      end
    end

    def validate_positive_integer!(value, label)
      integer = Integer(value)
      raise ValidationError, "#{label} must be positive" unless integer.positive?
    rescue ArgumentError, TypeError
      raise ValidationError, "#{label} must be an integer"
    end
  end
end
