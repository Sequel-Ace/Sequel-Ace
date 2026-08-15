# frozen_string_literal: true

require "time"

module SequelAceRelease
  module ReleasePublisher
    # The user-publisher bridge ends before its repository-only PAT expires.
    # Historical publisher epochs remain accepted for archived releases.
    USER_LOGIN = "Jason-Morcos".freeze
    USER_ID = 10_710_367
    CURRENT_MINIMUM_BUILD = 20_109
    RELEASE_APP_ID = 4_541_115
    RELEASE_APP_SLUGS = %w[sequel-ace-release-automation sequel-ace-releases].freeze
    RELEASE_APP_LOGINS = RELEASE_APP_SLUGS.map { |slug| "#{slug}[bot]" }.freeze
    RELEASE_APP_LOGIN = RELEASE_APP_LOGINS.first
    USER_PUBLISHER_CUTOFF = Time.utc(2027, 8, 14).freeze
    USER_PUBLISHER_SAFETY_WINDOW = 15 * 60
    TAG_PATTERN = %r{\A(?:production|beta)/\d+\.\d+\.\d+-([1-9]\d*)\z}.freeze
    ZONED_TIMESTAMP_PATTERN = /(?:Z|[+-]\d{2}:\d{2})\z/.freeze

    module_function

    def active_mode(at: Time.now.utc)
      current_time = publication_time(at)
      return :app if current_time >= USER_PUBLISHER_CUTOFF
      if current_time >= USER_PUBLISHER_CUTOFF - USER_PUBLISHER_SAFETY_WINDOW
        raise ValidationError,
              "new GitHub release creation is paused during the publisher cutoff safety window"
      end

      :user
    end

    def authorized?(tag:, login:, id: nil, created_at: nil, at: Time.now.utc)
      build = tag.to_s[TAG_PATTERN, 1]&.to_i
      return false unless build
      release_created_at = publication_time(created_at || at)
      (login == USER_LOGIN && id == USER_ID && build >= CURRENT_MINIMUM_BUILD &&
        release_created_at < USER_PUBLISHER_CUTOFF) ||
        (RELEASE_APP_LOGINS.include?(login) && build >= CURRENT_MINIMUM_BUILD &&
          release_created_at >= USER_PUBLISHER_CUTOFF)
    rescue ArgumentError, TypeError
      false
    end

    def validate!(tag:, login:, id: nil, created_at: nil, at: Time.now.utc)
      return login if authorized?(tag: tag, login: login, id: id, created_at: created_at, at: at)

      raise ValidationError, "GitHub release publisher is not authorized for #{tag}"
    end

    def validate_user_publisher_token!(token)
      value = token.to_s
      unless value.start_with?("github_pat_") && value.length > "github_pat_".length
        raise ValidationError,
              "GitHub user publisher credential must be a fine-grained personal access token"
      end

      value
    end

    def legacy_client_compatibility_required?(tag:, created_at:)
      build = tag.to_s[TAG_PATTERN, 1]&.to_i
      return false unless build && build >= CURRENT_MINIMUM_BUILD

      publication_time(created_at) < USER_PUBLISHER_CUTOFF
    rescue ArgumentError, TypeError
      raise ValidationError, "GitHub release publication time is malformed"
    end

    def publication_time(value)
      return value.utc if value.is_a?(Time)
      if value.is_a?(String) && value.match?(ZONED_TIMESTAMP_PATTERN)
        return Time.iso8601(value).utc
      end

      raise ArgumentError, "GitHub release publication time is malformed"
    end
  end
end
