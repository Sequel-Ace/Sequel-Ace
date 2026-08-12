# frozen_string_literal: true

module SequelAceRelease
  class DeploymentGuard
    def validate!(
      actor:, triggering_actor:, mode:, ref:, current_sha:, expected_sha:, channel:,
      version:, confirmation:, enabled:, recovery_tag: nil
    )
      Config.validate_channel!(channel)
      Version.validate!(version)
      raise ValidationError, "release publishing is disabled" unless enabled.to_s == "true"
      raise ValidationError, "release mode must be start or resume" unless %w[start resume].include?(mode)
      automated_recovery = actor == Config::ACTIONS_BOT && triggering_actor == Config::ACTIONS_BOT
      if automated_recovery
        unless mode == "resume" && recovery_tag.to_s.match?(%r{\A(?:production|beta)/\d+\.\d+\.\d+-[1-9]\d*\z})
          raise ValidationError, "automated recovery requires resume mode and an exact predecessor tag"
        end
      else
        raise ValidationError, "unauthorized release actor" unless Config::AUTHORIZED_ACTORS.include?(actor)
        unless Config::AUTHORIZED_ACTORS.include?(triggering_actor)
          raise ValidationError, "unauthorized release triggering actor"
        end
        raise ValidationError, "human release dispatch must not supply a recovery tag" unless recovery_tag.to_s.empty?
      end
      raise ValidationError, "releases must be dispatched from main" unless ref == "refs/heads/main"
      raise ValidationError, "current main SHA is malformed" unless Config.valid_git_sha?(current_sha)
      raise ValidationError, "frozen main SHA is malformed" unless Config.valid_git_sha?(expected_sha)
      current_sha = current_sha.to_s.downcase
      expected_sha = expected_sha.to_s.downcase
      main_advanced = current_sha != expected_sha
      if main_advanced && mode != "resume"
        raise ValidationError, "main changed after release approval"
      end

      expected_confirmation = "RELEASE #{channel} #{version}"
      unless confirmation == expected_confirmation
        raise ValidationError, "typed confirmation must be exactly #{expected_confirmation.inspect}"
      end

      {
        "actor" => actor,
        "triggering_actor" => triggering_actor,
        "mode" => mode,
        "ref" => ref,
        "dispatch_main_sha" => current_sha,
        "approved_main_sha" => expected_sha,
        "requires_release_ancestor_validation" => main_advanced,
        "automated_recovery" => automated_recovery,
        "recovery_tag" => recovery_tag,
        "channel" => channel,
        "version" => version
      }
    end
  end
end
