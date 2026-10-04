# frozen_string_literal: true

module SequelAceRelease
  module ReleasePublisher
    # Publisher authorization is based on GitHub-controlled numeric identities,
    # not release dates, build ranges, or mutable account names. Compatibility
    # with shipped updater payloads is evaluated separately.
    USER_LOGIN = "Jason-Morcos".freeze
    USER_ID = 10_710_367
    RELEASE_APP_ID = 4_541_115
    RELEASE_APP_BOT_ID = 315_153_817
    RELEASE_APP_LOGIN = "sequel-ace-release-automation[bot]".freeze
    TAG_PATTERN = %r{\A(?:production|beta)/\d+\.\d+\.\d+-[1-9]\d*\z}.freeze
    LOGIN_PATTERN = /\A[A-Za-z0-9-]+(?:\[bot\])?\z/.freeze

    module_function

    def validate_tag!(tag)
      return tag if tag.to_s.match?(TAG_PATTERN)

      raise ValidationError, "GitHub release tag is malformed"
    end

    def authorized?(tag:, login:, id: nil, **_unused)
      return false unless tag.to_s.match?(TAG_PATTERN) && login.to_s.match?(LOGIN_PATTERN)

      (id == USER_ID && !login.to_s.end_with?("[bot]")) ||
        (id == RELEASE_APP_BOT_ID && login.to_s.end_with?("[bot]"))
    end

    def validate!(tag:, login:, id: nil, **options)
      return login if authorized?(tag: tag, login: login, id: id, **options)

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

  end
end
