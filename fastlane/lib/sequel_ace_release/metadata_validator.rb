# frozen_string_literal: true

require "time"

module SequelAceRelease
  class MetadataValidator
    REQUIRED_LOCALIZATION_FIELDS = %w[
      description keywords whatsNew promotionalText supportUrl marketingUrl
    ].freeze
    REQUIRED_REVIEW_FIELDS = %w[
      contactFirstName contactLastName contactEmail contactPhone
    ].freeze

    def self.app_version_state(resource)
      attributes = resource.fetch("attributes", {})
      attributes["appVersionState"] || attributes["appStoreState"]
    end

    def validate!(snapshot:, expected_build:, expected_notes: nil, expected_promotional_text: nil, require_live: false, minimum_release_time: nil)
      version = snapshot.fetch("version")
      localization = snapshot.fetch("localization")
      review_detail = snapshot["review_detail"]
      selected_build = snapshot["selected_build"]
      phased_release = snapshot["phased_release"]
      reset_ratings_request = snapshot["reset_ratings_request"]

      validate_localization!(localization, expected_notes, expected_promotional_text)
      validate_screenshots!(snapshot.fetch("screenshot_sets"))
      validate_review_detail!(review_detail)
      validate_selected_build!(selected_build, expected_build)
      validate_release_configuration!(version, phased_release, reset_ratings_request, minimum_release_time)
      validate_live!(version, phased_release) if require_live
      true
    end

    private

    def validate_localization!(resource, expected_notes, expected_promotional_text)
      attributes = resource.fetch("attributes", {})
      missing = REQUIRED_LOCALIZATION_FIELDS.select { |field| attributes[field].to_s.strip.empty? }
      raise ValidationError, "#{Config::LOCALE} localization is missing: #{missing.join(', ')}" unless missing.empty?
      if expected_notes
        actual = normalize_newlines(attributes["whatsNew"].to_s.strip)
        expected = normalize_newlines(expected_notes.to_s.strip)
        raise ValidationError, "App Store release notes readback does not match the approved notes" unless actual == expected
      end
      if expected_promotional_text
        actual = normalize_newlines(attributes["promotionalText"].to_s.strip)
        expected = normalize_newlines(expected_promotional_text.to_s.strip)
        raise ValidationError, "Promotional Text readback does not match the preserved live value" unless actual == expected
      end
    end

    def validate_screenshots!(sets)
      screenshots = Array(sets).flat_map { |set| Array(set["screenshots"]) }
      unless screenshots.length == Config::EXPECTED_SCREENSHOT_COUNT
        raise ValidationError, "expected #{Config::EXPECTED_SCREENSHOT_COUNT} screenshots, found #{screenshots.length}"
      end

      incomplete = screenshots.filter_map do |screenshot|
        state = screenshot.dig("attributes", "assetDeliveryState", "state")
        screenshot["id"] unless state == "COMPLETE"
      end
      raise ValidationError, "screenshot delivery is incomplete for #{incomplete.length} asset(s)" unless incomplete.empty?
    end

    def validate_review_detail!(resource)
      raise ValidationError, "App Review information is missing" unless resource

      attributes = resource.fetch("attributes", {})
      missing = REQUIRED_REVIEW_FIELDS.select { |field| attributes[field].to_s.strip.empty? }
      if attributes["demoAccountRequired"] == true
        missing.concat(%w[demoAccountName demoAccountPassword].select { |field| attributes[field].to_s.strip.empty? })
      end
      raise ValidationError, "App Review information is missing required field(s): #{missing.join(', ')}" unless missing.empty?
    end

    def validate_selected_build!(resource, expected_build)
      raise ValidationError, "no build is selected for the App Store version" unless resource

      actual = resource.dig("attributes", "version").to_s
      raise ValidationError, "selected App Store build #{actual} does not match #{expected_build}" unless actual == expected_build.to_s
    end

    def validate_release_configuration!(version, phased_release, reset_ratings_request, minimum_release_time)
      attributes = version.fetch("attributes", {})
      raise ValidationError, "App Store version must use SCHEDULED release" unless attributes["releaseType"] == "SCHEDULED"
      raise ValidationError, "ratings reset must remain disabled" if reset_ratings_request
      raise ValidationError, "seven-day phased release is not configured" unless phased_release

      return unless minimum_release_time

      actual = Time.parse(attributes.fetch("earliestReleaseDate"))
      minimum = minimum_release_time.is_a?(Time) ? minimum_release_time : Time.parse(minimum_release_time.to_s)
      raise ValidationError, "scheduled release is earlier than the approved minimum" if actual < minimum
    rescue KeyError, ArgumentError, TypeError
      raise ValidationError, "scheduled release date is missing or malformed"
    end

    def validate_live!(version, phased_release)
      state = self.class.app_version_state(version)
      unless state == "READY_FOR_DISTRIBUTION"
        raise ValidationError, "App Store version is not live (state: #{state || 'unknown'})"
      end

      phased_state = phased_release.dig("attributes", "phasedReleaseState")
      unless %w[ACTIVE COMPLETE].include?(phased_state)
        raise ValidationError, "phased release is not active (state: #{phased_state || 'unknown'})"
      end
    end

    def normalize_newlines(value)
      value.gsub("\r\n", "\n")
    end
  end
end
