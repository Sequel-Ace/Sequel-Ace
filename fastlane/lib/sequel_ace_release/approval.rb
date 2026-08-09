# frozen_string_literal: true

require "digest"

module SequelAceRelease
  class Approval
    POLICY = "authoritative-production-cloud-next".freeze
    REQUIRED_KEYS = %w[
      channel target_version main_sha previous_tag base_sha app_store_notes release_notes_sha256
      observed_production_cloud_next_build build_policy
    ].freeze

    attr_reader :payload

    def initialize(
      channel:, target_version:, main_sha:, previous_tag:, base_sha:,
      app_store_notes:, release_notes_sha256:,
      observed_production_cloud_next_build:, build_policy: POLICY
    )
      @payload = {
        "channel" => Config.validate_channel!(channel),
        "target_version" => Version.validate!(target_version),
        "main_sha" => validate_sha!(main_sha, "main"),
        "previous_tag" => validate_tag!(previous_tag),
        "base_sha" => validate_sha!(base_sha, "base"),
        "app_store_notes" => validate_notes!(app_store_notes),
        "release_notes_sha256" => validate_digest!(release_notes_sha256),
        "observed_production_cloud_next_build" => validate_build!(observed_production_cloud_next_build),
        "build_policy" => build_policy
      }
      raise ValidationError, "unsupported build policy" unless build_policy == POLICY
    end

    def self.from_hash(value)
      missing = REQUIRED_KEYS - value.keys.map(&:to_s)
      raise ValidationError, "approval is missing: #{missing.join(', ')}" unless missing.empty?

      new(**value.transform_keys(&:to_sym).slice(*REQUIRED_KEYS.map(&:to_sym)))
    end

    def sha256
      Digest::SHA256.hexdigest(CanonicalJSON.dump(payload))
    end

    def verify!(expected)
      unless expected.to_s.match?(/\A[0-9a-f]{64}\z/) && secure_compare(sha256, expected)
        raise ValidationError, "approval SHA-256 does not match the immutable release inputs"
      end

      true
    end

    def to_h
      payload.merge("sha256" => sha256)
    end

    private

    def validate_sha!(value, label)
      return value if value.to_s.match?(/\A[0-9a-f]{40,64}\z/i)

      raise ValidationError, "#{label} SHA is malformed"
    end

    def validate_tag!(value)
      return value if value.to_s.match?(%r{\A(?:production|beta)/\d+\.\d+\.\d+-\d+\z})

      raise ValidationError, "previous tag is malformed"
    end

    def validate_notes!(value)
      notes = value.to_s.strip
      raise ValidationError, "App Store release notes must not be empty" if notes.empty?
      raise ValidationError, "App Store release notes exceed Apple's 4,000 character limit" if notes.length > 4_000

      notes
    end

    def validate_digest!(value)
      return value if value.to_s.match?(/\A[0-9a-f]{64}\z/)

      raise ValidationError, "GitHub release-body SHA-256 is malformed"
    end

    def validate_build!(value)
      build = Integer(value)
      raise ValidationError, "observed Production Cloud next build must be positive" unless build.positive?

      build
    rescue ArgumentError, TypeError
      raise ValidationError, "observed Production Cloud next build must be an integer"
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |difference, (a, b)| difference | (a ^ b) }.zero?
    end
  end
end
