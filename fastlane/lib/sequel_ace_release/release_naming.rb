# frozen_string_literal: true

module SequelAceRelease
  class ReleaseNaming
    attr_reader :channel, :version, :build, :iteration

    def initialize(channel:, version:, build:, iteration: 1)
      @channel = Config.validate_channel!(channel)
      @version = Version.validate!(version)
      @build = Integer(build)
      @iteration = Integer(iteration)
      raise ValidationError, "build must be positive" unless @build.positive?
      raise ValidationError, "iteration must be positive" unless @iteration.positive?
    end

    def tag
      "#{channel}/#{version}-#{build}"
    end

    def title
      if channel == "production"
        "#{version} (#{build}) - Release Candidate #{iteration}"
      else
        "#{version} (#{build}) Beta #{iteration}"
      end
    end

    def final_title
      "#{version} (#{build})"
    end

    def branch
      "prepare-release/#{version}-#{build}-#{iteration}"
    end

    def public_artifacts
      if channel == "production"
        ["Sequel-Ace-#{version}.zip"]
      else
        [
          "Sequel-Ace-#{version}-beta#{iteration}.zip",
          "Sequel-Ace-#{version}-beta#{iteration}-alpha.zip"
        ]
      end
    end

    def ghcr_tag
      "#{channel}-#{version}-#{build}"
    end

    def to_h
      {
        "channel" => channel,
        "version" => version,
        "build" => build,
        "iteration" => iteration,
        "tag" => tag,
        "title" => title,
        "final_title" => final_title,
        "branch" => branch,
        "public_artifacts" => public_artifacts,
        "ghcr_tag" => ghcr_tag
      }
    end
  end
end
