# frozen_string_literal: true

module SequelAceRelease
  class BuildReconciler
    Result = Struct.new(:target_build, :observed_cloud_next_build, :baseline, :reason, :skipped_runs, keyword_init: true) do
      def to_h
        {
          "target_build" => target_build,
          "observed_cloud_next_build" => observed_cloud_next_build,
          "baseline" => baseline,
          "reason" => reason,
          "skipped_production_builds" => skipped_runs
        }
      end
    end

    def reconcile(source_build:, highest_tag_build:, highest_asc_build:, cloud_next_build:, cloud_runs:, source_tagged:, source_is_release_tip: true)
      source = positive_integer(source_build, "source build")
      tag = nonnegative_integer(highest_tag_build, "highest tag build")
      asc = nonnegative_integer(highest_asc_build, "highest App Store Connect build")
      observed_cloud_next = positive_integer(cloud_next_build, "Xcode Cloud next build")
      raise ValidationError, "Production release tag build #{tag} is ahead of source build #{source}" if tag > source

      baseline = [source, tag, asc].max
      indexed_runs = Array(cloud_runs).each_with_object({}) do |run, result|
        number = integer_or_nil(run["number"] || run[:number])
        result[number] = stringify_keys(run) if number
      end

      if observed_cloud_next == source && !source_tagged && source > [tag, asc].max
        unless source_is_release_tip
          raise ValidationError, "merged-but-untagged recovery requires the release preparation merge to remain at main HEAD"
        end
        consumed_at_or_after_source = indexed_runs.keys.select { |number| number >= source }
        unless consumed_at_or_after_source.empty?
          raise ValidationError,
                "Production Xcode Cloud already consumed or advanced beyond source build #{source}: " \
                "#{consumed_at_or_after_source.sort.join(', ')}"
        end
        return Result.new(
          target_build: source,
          observed_cloud_next_build: observed_cloud_next,
          baseline: baseline,
          reason: "resume_after_merge",
          skipped_runs: []
        )
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

      Result.new(
        target_build: cloud_next,
        observed_cloud_next_build: observed_cloud_next,
        baseline: baseline,
        reason: skipped.empty? ? "normal_increment" : "self_healed_cloud_burns",
        skipped_runs: skipped
      )
    end

    private

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
