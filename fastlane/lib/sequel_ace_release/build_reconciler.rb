# frozen_string_literal: true

module SequelAceRelease
  class BuildReconciler
    Result = Struct.new(
      :target_build, :observed_cloud_next_build, :baseline, :reason,
      :skipped_runs, :source_release_commit_sha, keyword_init: true
    ) do
      def to_h
        {
          "target_build" => target_build,
          "observed_cloud_next_build" => observed_cloud_next_build,
          "baseline" => baseline,
          "reason" => reason,
          "skipped_production_builds" => skipped_runs,
          "source_release_commit_sha" => source_release_commit_sha
        }.compact
      end
    end

    def reconcile(
      source_build:, highest_tag_build:, highest_asc_build:, cloud_next_build:,
      cloud_runs:, source_tagged:, source_release_commit_sha: nil,
      expected_target_build: nil, recover_release_tag: nil,
      production_workflow_id: nil
    )
      source = positive_integer(source_build, "source build")
      tag = nonnegative_integer(highest_tag_build, "highest tag build")
      asc = nonnegative_integer(highest_asc_build, "highest App Store Connect build")
      observed_cloud_next = positive_integer(cloud_next_build, "Xcode Cloud next build")
      raise ValidationError, "canonical release tag build #{tag} is ahead of source build #{source}" if tag > source

      baseline = [source, tag, asc].max
      indexed_runs = Array(cloud_runs).each_with_object({}) do |run, result|
        number = integer_or_nil(run["number"] || run[:number])
        result[number] = stringify_keys(run) if number
      end

      if recover_release_tag
        return validate_expected_target!(recover_tagged_release(
          source: source,
          tag: tag,
          asc: asc,
          observed_cloud_next: observed_cloud_next,
          indexed_runs: indexed_runs,
          source_tagged: source_tagged,
          source_release_commit_sha: source_release_commit_sha,
          recover_release_tag: recover_release_tag,
          production_workflow_id: production_workflow_id
        ), expected_target_build)
      end

      if observed_cloud_next == source && !source_tagged && source > [tag, asc].max
        release_commit = validate_commit_sha!(source_release_commit_sha)
        consumed_at_or_after_source = indexed_runs.keys.select { |number| number >= source }
        unless consumed_at_or_after_source.empty?
          raise ValidationError,
                "Production Xcode Cloud already consumed or advanced beyond source build #{source}: " \
                "#{consumed_at_or_after_source.sort.join(', ')}"
        end
        return validate_expected_target!(Result.new(
          target_build: source,
          observed_cloud_next_build: observed_cloud_next,
          baseline: baseline,
          reason: "resume_after_merge",
          skipped_runs: [],
          source_release_commit_sha: release_commit
        ), expected_target_build)
      end

      if observed_cloud_next < baseline
        raise ValidationError, "Xcode Cloud next build #{observed_cloud_next} regressed below reconciled baseline #{baseline}"
      end

      # The configured next number is not exposed by Apple's public API. The
      # UI-observed value is therefore a lower bound at execution time: if a
      # Production run consumed it after approval, exact workflow-run evidence
      # advances the target. The contiguous-gap checks below still refuse any
      # unexplained jump.
      highest_consumed = indexed_runs.keys.max
      cloud_next = [observed_cloud_next, highest_consumed && highest_consumed + 1].compact.max
      if cloud_next <= baseline
        raise ValidationError, "Xcode Cloud next build #{cloud_next} must be greater than reconciled baseline #{baseline}"
      end

      skipped_numbers = ((baseline + 1)...cloud_next).to_a
      unexplained = skipped_numbers.reject { |number| indexed_runs.key?(number) }
      unless unexplained.empty?
        raise ValidationError, "unexplained Production Xcode Cloud build gap: #{unexplained.join(', ')}"
      end

      skipped = skipped_numbers.map do |number|
        run = indexed_runs.fetch(number)
        evidence = {
          "number" => number,
          "id" => run["id"],
          "completion_status" => run["completion_status"] || run["completionStatus"],
          "source_commit" => run["source_commit"] || run["sourceCommit"]
        }
        missing = evidence.select { |key, value| key != "number" && value.to_s.empty? }.keys
        unless missing.empty?
          raise ValidationError, "Production Xcode Cloud build #{number} is missing burn evidence: #{missing.join(', ')}"
        end
        evidence
      end

      validate_expected_target!(Result.new(
        target_build: cloud_next,
        observed_cloud_next_build: observed_cloud_next,
        baseline: baseline,
        reason: skipped.empty? ? "normal_increment" : "self_healed_cloud_burns",
        skipped_runs: skipped
      ), expected_target_build)
    end

    private

    def recover_tagged_release(
      source:, tag:, asc:, observed_cloud_next:, indexed_runs:, source_tagged:,
      source_release_commit_sha:, recover_release_tag:, production_workflow_id:
    )
      release_commit = validate_commit_sha!(source_release_commit_sha)
      unless recover_release_tag.to_s.match?(%r{\A(?:production|beta)/\d+\.\d+\.\d+-#{source}\z})
        raise ValidationError, "tag-only recovery does not match source build #{source}"
      end
      raise ValidationError, "tag-only recovery requires the exact canonical source tag" unless source_tagged && tag == source
      if asc > source
        raise ValidationError, "App Store Connect build #{asc} is ahead of tag-only recovery build #{source}"
      end
      unless production_workflow_id.to_s.match?(/\A[0-9A-F-]{36}\z/i)
        raise ValidationError, "tag-only recovery requires the exact Production workflow ID"
      end
      if observed_cloud_next < source || observed_cloud_next > source + 1
        raise ValidationError,
              "Xcode Cloud next build #{observed_cloud_next} is incompatible with tag-only recovery build #{source}"
      end

      later_runs = indexed_runs.keys.select { |number| number > source }
      unless later_runs.empty?
        raise ValidationError,
              "Production Xcode Cloud advanced beyond tag-only recovery build #{source}: #{later_runs.sort.join(', ')}"
      end

      source_run = indexed_runs[source]
      if asc == source && source_run.nil?
        raise ValidationError,
              "App Store Connect build #{source} has no exact Production run for tag-only recovery"
      end
      if source_run
        required = %w[id execution_progress source_commit git_reference workflow_id]
        missing = required.select { |key| source_run[key].to_s.empty? }
        unless missing.empty?
          raise ValidationError,
                "Production Xcode Cloud build #{source} is missing tag-only recovery evidence: #{missing.join(', ')}"
        end
        unless source_run["source_commit"].to_s.downcase == release_commit &&
               source_run["git_reference"] == recover_release_tag &&
               source_run["workflow_id"] == production_workflow_id
          raise ValidationError, "Production Xcode Cloud build #{source} does not match the tag-only recovery identity"
        end
      elsif observed_cloud_next != source
        raise ValidationError,
              "Xcode Cloud advanced past tag-only recovery build #{source} without its exact Production run"
      end

      Result.new(
        target_build: source,
        observed_cloud_next_build: observed_cloud_next,
        baseline: source,
        reason: "resume_after_tag",
        skipped_runs: [],
        source_release_commit_sha: release_commit
      )
    end

    def validate_commit_sha!(value)
      return value.to_s.downcase if Config.valid_git_sha?(value)

      raise ValidationError,
            "merged-but-untagged recovery requires an exact release preparation commit on main's first-parent history"
    end

    def validate_expected_target!(result, expected)
      return result if expected.nil?

      expected_build = positive_integer(expected, "expected target build")
      unless result.target_build == expected_build
        raise ValidationError,
              "Production Xcode Cloud target advanced from #{expected_build} to #{result.target_build}; " \
              "abort before merging or tagging"
      end

      result
    end

    def positive_integer(value, label)
      integer = Integer(value)
      raise ValidationError, "#{label} must be positive" unless integer.positive?

      integer
    rescue ArgumentError, TypeError
      raise ValidationError, "#{label} must be an integer"
    end

    def nonnegative_integer(value, label)
      integer = Integer(value || 0)
      raise ValidationError, "#{label} must not be negative" if integer.negative?

      integer
    rescue ArgumentError, TypeError
      raise ValidationError, "#{label} must be an integer"
    end

    def integer_or_nil(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def stringify_keys(value)
      value.each_with_object({}) { |(key, child), result| result[key.to_s] = child }
    end
  end
end
