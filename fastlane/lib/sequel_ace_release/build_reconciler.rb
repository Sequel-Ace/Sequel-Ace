# frozen_string_literal: true

module SequelAceRelease
  class BuildReconciler
    Result = Struct.new(
      :target_build, :baseline, :reason, :skipped_runs,
      :production_build_evidence, :source_release_commit_sha, keyword_init: true
    ) do
      def to_h
        {
          "target_build" => target_build,
          "baseline" => baseline,
          "reason" => reason,
          "production_build_evidence" => production_build_evidence,
          "skipped_production_builds" => skipped_runs,
          "source_release_commit_sha" => source_release_commit_sha
        }.compact
      end
    end

    def reconcile(
      source_build:, highest_tag_build:, highest_asc_build:, cloud_runs:,
      source_tagged:, source_release_commit_sha: nil, expected_target_build: nil,
      recover_release_tag: nil, production_workflow_id: nil
    )
      source = positive_integer(source_build, "source build")
      tag = nonnegative_integer(highest_tag_build, "highest tag build")
      asc = nonnegative_integer(highest_asc_build, "highest App Store Connect build")
      raise ValidationError, "canonical release tag build #{tag} is ahead of source build #{source}" if tag > source

      indexed_runs = index_runs(cloud_runs)
      highest_cloud_run = indexed_runs.values.max_by { |run| run.fetch("number") }
      highest_cloud = highest_cloud_run&.fetch("number") || 0
      consumed_baseline = [tag, asc, highest_cloud].max
      expected_next = consumed_baseline + 1
      evidence = build_evidence(
        source: source,
        tag: tag,
        asc: asc,
        highest_cloud_run: highest_cloud_run,
        consumed_baseline: consumed_baseline,
        expected_next: expected_next
      )

      if recover_release_tag
        return validate_expected_target!(recover_tagged_release(
          source: source,
          tag: tag,
          asc: asc,
          indexed_runs: indexed_runs,
          source_tagged: source_tagged,
          source_release_commit_sha: source_release_commit_sha,
          recover_release_tag: recover_release_tag,
          production_workflow_id: production_workflow_id,
          evidence: evidence
        ), expected_target_build)
      end

      if source == expected_next && !source_tagged
        release_commit = validate_commit_sha!(source_release_commit_sha)
        return validate_expected_target!(Result.new(
          target_build: source,
          baseline: consumed_baseline,
          reason: "resume_after_merge",
          skipped_runs: skipped_build_evidence(
            from: [tag, source - 1].min,
            to: source,
            indexed_runs: indexed_runs,
            highest_asc_build: asc
          ),
          production_build_evidence: evidence,
          source_release_commit_sha: release_commit
        ), expected_target_build)
      end

      if source > expected_next
        raise ValidationError,
              "source build #{source} is ahead of API-derived Production build #{expected_next}; " \
              "the forward-only history cannot be reconciled"
      end

      local_baseline = [source, tag].max
      skipped = skipped_build_evidence(
        from: local_baseline,
        to: expected_next,
        indexed_runs: indexed_runs,
        highest_asc_build: asc
      )
      reason = if expected_next == local_baseline + 1
                 "normal_increment"
               else
                 "self_healed_forward_jump"
               end

      validate_expected_target!(Result.new(
        target_build: expected_next,
        baseline: consumed_baseline,
        reason: reason,
        skipped_runs: skipped,
        production_build_evidence: evidence
      ), expected_target_build)
    end

    private

    def recover_tagged_release(
      source:, tag:, asc:, indexed_runs:, source_tagged:, source_release_commit_sha:,
      recover_release_tag:, production_workflow_id:, evidence:
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
      end

      Result.new(
        target_build: source,
        baseline: source,
        reason: "resume_after_tag",
        skipped_runs: [],
        production_build_evidence: evidence,
        source_release_commit_sha: release_commit
      )
    end

    def index_runs(cloud_runs)
      Array(cloud_runs).each_with_object({}) do |raw_run, result|
        run = stringify_keys(raw_run)
        number = positive_integer(run["number"], "Production Xcode Cloud run number")
        unless run["id"].to_s.match?(/\A[A-Za-z0-9-]+\z/)
          raise ValidationError, "Production Xcode Cloud build #{number} has a malformed run ID"
        end
        if result.key?(number)
          raise ValidationError, "Production Xcode Cloud returned duplicate build number #{number}"
        end

        result[number] = run.merge("number" => number)
      end
    end

    def build_evidence(source:, tag:, asc:, highest_cloud_run:, consumed_baseline:, expected_next:)
      {
        "policy" => Approval::POLICY,
        "source_build" => source,
        "highest_tag_build" => tag,
        "highest_asc_build" => asc,
        "highest_cloud_build" => highest_cloud_run&.fetch("number") || 0,
        "highest_observed_build" => consumed_baseline,
        "expected_next_build" => expected_next,
        "highest_cloud_run" => run_evidence(highest_cloud_run)
      }.compact
    end

    def skipped_build_evidence(from:, to:, indexed_runs:, highest_asc_build:)
      ((from + 1)...to).map do |number|
        if indexed_runs.key?(number)
          run_evidence(indexed_runs.fetch(number)).merge(
            "number" => number,
            "reason" => "production_cloud_run"
          )
        else
          later_run = indexed_runs.values.select { |run| run.fetch("number") > number }
                                  .min_by { |run| run.fetch("number") }
          if later_run
            {
              "number" => number,
              "reason" => "production_cloud_counter_jump",
              "evidenced_by_run_id" => later_run.fetch("id"),
              "evidenced_by_build" => later_run.fetch("number")
            }
          elsif highest_asc_build >= number
            {
              "number" => number,
              "reason" => "app_store_connect_counter_floor",
              "evidenced_by_build" => highest_asc_build
            }
          else
            raise ValidationError, "unexplained Production build gap: #{number}"
          end
        end
      end
    end

    def run_evidence(run)
      return nil unless run

      {
        "id" => run.fetch("id"),
        "number" => run.fetch("number"),
        "execution_progress" => run["execution_progress"] || run["executionProgress"],
        "completion_status" => run["completion_status"] || run["completionStatus"],
        "source_commit" => run["source_commit"] || run["sourceCommit"],
        "destination_commit" => run["destination_commit"] || run["destinationCommit"]
      }.compact
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
              "API-derived Production build advanced from #{expected_build} to #{result.target_build}; " \
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

    def stringify_keys(value)
      value.each_with_object({}) { |(key, child), result| result[key.to_s] = child }
    end
  end
end
