# frozen_string_literal: true

require "digest"

module SequelAceRelease
  class Notes
    SUBSTANTIAL_CHANGE = /\b(?:overhaul|redesign|substantial|major rework|rewrite)\b/i
    HEADINGS = {
      "added" => "Added",
      "fixed" => "Fixed",
      "changed" => "Changed",
      "removed" => "Removed",
      "infra" => "Infrastructure"
    }.freeze

    attr_reader :changes, :repository_url

    def initialize(changes:, repository_url: Config::REPOSITORY_URL)
      @changes = changes
      @repository_url = repository_url
    end

    def recommended_bump
      user_facing_addition = changes.any? { |change| change.category == "added" }
      substantial_change = changes.any? do |change|
        change.category != "infra" && change.title.to_s.match?(SUBSTANTIAL_CHANGE)
      end
      user_facing_addition || substantial_change ? "minor" : "patch"
    end

    def app_store_draft
      visible = changes.reject { |change| change.category == "infra" }.first(8)
      return "This update includes maintenance improvements and bug fixes." if visible.empty?

      visible.map { |change| "• #{sentence(change.title)}" }.join("\n")
    end

    def github_body(app_store_notes:, base_tag:, head_ref:, contributors: {})
      sections = ["## App Store Release Notes", "", app_store_notes.strip, "", "## What's Changed", ""]
      GitRepository::CATEGORY_ORDER.each do |category|
        entries = changes.select { |change| change.category == category }
        next if entries.empty?

        sections << "### #{HEADINGS.fetch(category)}"
        entries.each { |change| sections << entry(change) }
        sections << ""
      end

      new_contributors = contributors.values.uniq.compact.sort
      unless new_contributors.empty?
        sections << "## New Contributors"
        new_contributors.each { |login| sections << "- @#{login}" }
        sections << ""
      end

      sections << "**Full Changelog**: #{repository_url}/compare/#{base_tag}...#{head_ref}"
      sections.join("\n").gsub(/\n{3,}/, "\n\n").strip + "\n"
    end

    def sha256(body)
      Digest::SHA256.hexdigest(body)
    end

    private

    def sentence(title)
      value = title.strip
      value = value[0].upcase + value[1..] if value.match?(/\A[a-z]/)
      value.end_with?(".", "!", "?") ? value : "#{value}."
    end

    def entry(change)
      short = change.sha[0, 9]
      commit_link = "#{repository_url}/commit/#{change.sha}"
      links = ["[#{short}](#{commit_link})"]
      links << "[##{change.pr_number}](#{repository_url}/pull/#{change.pr_number})" if change.pr_number
      "- #{change.title} (#{links.join(', ')})"
    end
  end
end
