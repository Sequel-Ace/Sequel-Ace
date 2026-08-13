# frozen_string_literal: true

require "pathname"

module SequelAceRelease
  module Config
    REPOSITORY = "Sequel-Ace/Sequel-Ace"
    REPOSITORY_OWNER = "Sequel-Ace"
    REPOSITORY_URL = "https://github.com/#{REPOSITORY}"
    PRODUCTION_APP_ID = "1518036000"
    ALPHA_APP_ID = "1594104035"
    PRODUCTION_BUNDLE_ID = "com.sequel-ace.sequel-ace"
    ALPHA_BUNDLE_ID = "com.sequel-ace.sequel-ace-beta"
    TEAM_ID = "NKQ4HJ66PX"
    LOCALE = "en-US"
    EXPECTED_SCREENSHOT_COUNT = 10
    SCHEMA_VERSION = 2
    GIT_SHA_PATTERN = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i.freeze
    AUTHORIZED_ACTORS = %w[Jason-Morcos Kaspik].freeze
    ACTIONS_BOT = "github-actions[bot]".freeze
    CHANNELS = %w[production beta].freeze
    MANIFEST_STATES = %w[
      planned prepared pull_request_open merged prerelease_created
      cloud_running artifacts_verified archived submitted finalizing live failed
    ].freeze

    PROJECT_FILES = {
      "sequel-ace.xcodeproj/project.pbxproj" => { current: 4, dylib: 0 },
      "Frameworks/QueryKit/QueryKit.xcodeproj/project.pbxproj" => { current: 4, dylib: 1 },
      "Frameworks/SPMySQLFramework/SPMySQLFramework.xcodeproj/project.pbxproj" => { current: 5, dylib: 5 }
    }.freeze

    PLIST_FILES = %w[
      Resources/Plists/Info.plist
      Resources/Plists/TunnelAssistant-Info.plist
      Resources/Plists/Unit\ Tests-Info.plist
      Frameworks/QueryKit/Resources/Info.plist
      Frameworks/QueryKit/Resources/Tests-Info.plist
      Frameworks/SPMySQLFramework/Resources/Info.plist
      Frameworks/SPMySQLFramework/SPMySQL\ Unit\ Tests/Info.plist
    ].freeze

    module_function

    def repo_root
      @repo_root ||= Pathname.new(__dir__).join("../../..").expand_path
    end

    def validate_channel!(channel)
      return channel if CHANNELS.include?(channel)

      raise ValidationError, "channel must be one of: #{CHANNELS.join(', ')}"
    end

    def valid_git_sha?(value)
      value.to_s.match?(GIT_SHA_PATTERN)
    end

    def app_id(channel)
      validate_channel!(channel)
      channel == "production" ? PRODUCTION_APP_ID : ALPHA_APP_ID
    end

    def bundle_id(channel)
      validate_channel!(channel)
      channel == "production" ? PRODUCTION_BUNDLE_ID : ALPHA_BUNDLE_ID
    end
  end
end
