# frozen_string_literal: true

module SequelAceRelease
  class DeploymentGuard
    def validate!(actor:, ref:, current_sha:, expected_sha:, channel:, version:, cloud_next_build:, confirmation:, enabled:)
      Config.validate_channel!(channel)
      Version.validate!(version)
      raise ValidationError, "release publishing is disabled" unless enabled.to_s == "true"
      raise ValidationError, "unauthorized release actor" unless Config::AUTHORIZED_ACTORS.include?(actor)
      raise ValidationError, "releases must be dispatched from main" unless ref == "refs/heads/main"
      raise ValidationError, "current main SHA is malformed" unless current_sha.to_s.match?(/\A[0-9a-f]{40,64}\z/i)
      raise ValidationError, "frozen main SHA is malformed" unless expected_sha.to_s.match?(/\A[0-9a-f]{40,64}\z/i)
      raise ValidationError, "main changed after release approval" unless current_sha == expected_sha
      raise ValidationError, "Xcode Cloud next build must be positive" unless Integer(cloud_next_build).positive?

      expected_confirmation = "RELEASE #{channel} #{version}"
      unless confirmation == expected_confirmation
        raise ValidationError, "typed confirmation must be exactly #{expected_confirmation.inspect}"
      end

      {
        "actor" => actor,
        "ref" => ref,
        "main_sha" => current_sha,
        "channel" => channel,
        "version" => version,
        "cloud_next_build" => Integer(cloud_next_build)
      }
    rescue ArgumentError, TypeError
      raise ValidationError, "Xcode Cloud next build must be an integer"
    end
  end
end
