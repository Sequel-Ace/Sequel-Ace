# frozen_string_literal: true

module SequelAceRelease
  class Planner
    AUTOMATED_RELEASE_TITLE = /\APrepare \d+\.\d+\.\d+ \([1-9]\d*\) release\z/.freeze

    def initialize(git: GitRepository.new, github: nil, version_files: VersionFiles.new)
      @git = git
      @github = github
      @version_files = version_files
    end

    def plan(channel:, target_version: nil, base_tag: nil, main_ref: "HEAD", app_store_notes: nil)
      Config.validate_channel!(channel)
      main_sha = @git.sha(main_ref)
      release_notes_head_ref = resolve_release_notes_head_ref(main_ref)
      release_notes_head_sha = @git.sha(release_notes_head_ref)
      release_catalog = @github ? @github.releases : []
      stable = base_tag || select_base_tag(channel, target_version, release_catalog)
      raise ValidationError, "could not determine a prior release tag" if stable.to_s.empty?

      base_sha = @git.sha(stable)
      changes = @git.changes(base_ref: stable, head_ref: release_notes_head_ref)
      raise ValidationError, "there are no changes since #{stable}" if changes.empty?

      notes = Notes.new(changes: changes)
      base_match = stable.match(%r{\A(?:production|beta)/(\d+\.\d+\.\d+)-([1-9]\d*)\z})
      raise ValidationError, "base tag #{stable} is malformed" unless base_match

      base_version = base_match[1]
      later_beta = channel == "beta" && target_version && stable.start_with?("beta/#{target_version}-")
      recommended_bump = later_beta ? "same" : notes.recommended_bump
      recommendation = later_beta ? target_version : Version.bump(base_version, recommended_bump)
      chosen_version = target_version || recommendation
      Version.validate!(chosen_version)
      if !later_beta && !Version.compare(chosen_version, base_version).positive?
        raise ValidationError, "target version #{chosen_version} must be newer than #{base_version}"
      end
      changelog_base_tag = if later_beta
                             select_changelog_base_tag(stable, chosen_version, release_catalog)
                           else
                             stable
                           end
      if changelog_base_tag.to_s.empty?
        raise ValidationError, "could not determine the Production ancestor for the cumulative changelog"
      end
      changelog_base_sha = @git.sha(changelog_base_tag)
      human_notes = app_store_notes.to_s.strip
      human_notes = notes.app_store_draft if human_notes.empty?
      contributors = contributor_map(changes)
      release_body = notes.github_body(
        app_store_notes: human_notes,
        base_tag: stable,
        head_ref: release_notes_head_sha,
        contributors: contributors
      )
      release_notes_sha256 = notes.sha256(release_body)
      iteration = next_iteration(channel, chosen_version, release_catalog)
      approval = Approval.new(
        channel: channel,
        target_version: chosen_version,
        main_sha: main_sha,
        previous_tag: stable,
        base_sha: base_sha,
        changelog_base_tag: changelog_base_tag,
        changelog_base_sha: changelog_base_sha,
        app_store_notes: human_notes,
        release_notes_sha256: release_notes_sha256
      )
      {
        "schema_version" => Config::SCHEMA_VERSION,
        "channel" => channel,
        "current_source" => @version_files.current,
        "base_tag" => stable,
        "base_sha" => base_sha,
        "changelog_base_tag" => changelog_base_tag,
        "changelog_base_sha" => changelog_base_sha,
        "main_sha" => main_sha,
        "release_notes_head_sha" => release_notes_head_sha,
        "recommended_bump" => recommended_bump,
        "recommended_version" => recommendation,
        "target_version" => chosen_version,
        "iteration" => iteration,
        "build_policy" => approval.payload.fetch("build_policy"),
        "changes" => changes.map(&:to_h),
        "app_store_notes" => human_notes,
        "github_release_body" => release_body,
        "release_notes_sha256" => release_notes_sha256,
        "approval" => approval.to_h
      }.compact
    end

    private

    def resolve_release_notes_head_ref(main_ref)
      return main_ref unless @git.respond_to?(:parents)

      parents = @git.parents(main_ref)
      return main_ref unless parents.length == 2

      merge_changes = @git.changes(base_ref: parents.first, head_ref: main_ref)
      return main_ref unless merge_changes.length == 1

      change = merge_changes.first
      return main_ref unless change.pr_number && change.title.to_s.match?(AUTOMATED_RELEASE_TITLE)

      parents.first
    end

    def select_base_tag(channel, target_version, releases)
      parsed = parsed_releases(releases)

      if channel == "beta" && target_version
        beta = parsed.select { |item| item[:channel] == "beta" && item[:version] == target_version }
                     .max_by { |item| [item[:build], item[:published_at]] }
        return beta[:tag] if beta
      end

      production = parsed.select { |item| item[:channel] == "production" && !item[:prerelease] }
                         .max_by { |item| [Version.parts(item[:version]), item[:build], item[:published_at]] }
      return production[:tag] if production

      @git.latest_release_tag(channel: "production")
    end

    def select_changelog_base_tag(beta_tag, target_version, releases)
      stable_ancestors = parsed_releases(releases).select do |item|
        item[:channel] == "production" &&
          !item[:prerelease] &&
          Version.compare(item[:version], target_version).negative? &&
          @git.ancestor?(item[:tag], beta_tag)
      end
      stable_ancestors.max_by do |item|
        [Version.parts(item[:version]), item[:build], item[:published_at]]
      end&.fetch(:tag, nil)
    end

    def parsed_releases(releases)
      releases.filter_map do |release|
        next if release["draft"] == true

        tag = release["tag_name"]
        match = tag.to_s.match(%r{\A(production|beta)/(\d+\.\d+\.\d+)-([1-9]\d*)\z})
        next unless match

        {
          tag: tag,
          channel: match[1],
          version: match[2],
          build: Integer(match[3]),
          prerelease: release["prerelease"] == true,
          published_at: release["published_at"].to_s
        }
      end
    end

    def contributor_map(changes)
      return {} unless @github

      @github.new_contributors(changes.filter_map(&:pr_number).uniq)
    rescue APIError
      # Contributor enrichment is non-critical; the full change list remains intact.
      {}
    end

    def next_iteration(channel, version, releases)
      matching = releases.filter_map do |release|
        tag = release["tag_name"].to_s
        match = tag.match(%r{\A#{Regexp.escape(channel)}/#{Regexp.escape(version)}-([1-9]\d*)\z})
        next unless match
        next unless release["prerelease"] == true

        title = release["name"].to_s
        title_match = if channel == "production"
                        title.match(/Release Candidate\s+(\d+)\z/i)
                      else
                        title.match(/Beta\s+(\d+)\z/i)
                      end
        title_match ? Integer(title_match[1]) : 1
      end
      (matching.max || 0) + 1
    end
  end
end
