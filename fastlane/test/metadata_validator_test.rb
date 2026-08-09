# frozen_string_literal: true

require "test_helper"

class MetadataValidatorTest < Minitest::Test
  def setup
    @validator = SequelAceRelease::MetadataValidator.new
    @minimum = Time.parse("2026-08-11T16:00:00Z")
  end

  def test_complete_metadata_passes
    assert @validator.validate!(
      snapshot: metadata_snapshot,
      expected_build: 20_105,
      expected_notes: "A focused release note.",
      minimum_release_time: @minimum
    )
  end

  def test_promotional_text_is_independent_required_gate
    snapshot = metadata_snapshot
    snapshot["localization"]["attributes"]["promotionalText"] = nil
    error = assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: snapshot, expected_build: 20_105)
    end
    assert_includes error.message, "promotionalText"
  end

  def test_promotional_text_must_equal_the_preserved_live_value
    error = assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(
        snapshot: metadata_snapshot,
        expected_build: 20_105,
        expected_promotional_text: "A different promotion."
      )
    end
    assert_includes error.message, "preserved live value"
  end

  def test_exact_screenshot_count_and_delivery_are_required
    snapshot = metadata_snapshot
    snapshot["screenshot_sets"].first["screenshots"].pop
    assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: snapshot, expected_build: 20_105)
    end

    snapshot = metadata_snapshot
    snapshot["screenshot_sets"].first["screenshots"].first["attributes"]["assetDeliveryState"]["state"] = "PROCESSING"
    assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: snapshot, expected_build: 20_105)
    end
  end

  def test_wrong_build_and_ratings_reset_abort
    assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: metadata_snapshot, expected_build: 20_106)
    end

    snapshot = metadata_snapshot
    snapshot["reset_ratings_request"] = { "id" => "reset-request" }
    assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: snapshot, expected_build: 20_105)
    end
  end

  def test_schedule_under_seventy_two_hours_and_missing_review_fields_abort
    snapshot = metadata_snapshot
    snapshot["version"]["attributes"]["earliestReleaseDate"] = "2026-08-10T16:00:00Z"
    assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(
        snapshot: snapshot,
        expected_build: 20_105,
        minimum_release_time: @minimum
      )
    end

    snapshot = metadata_snapshot
    snapshot["review_detail"]["attributes"]["contactEmail"] = ""
    error = assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: snapshot, expected_build: 20_105)
    end
    assert_includes error.message, "contactEmail"
  end

  def test_live_gate_requires_distribution_and_active_phase
    assert @validator.validate!(
      snapshot: metadata_snapshot(state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE"),
      expected_build: 20_105,
      require_live: true
    )

    assert_raises(SequelAceRelease::ValidationError) do
      @validator.validate!(snapshot: metadata_snapshot, expected_build: 20_105, require_live: true)
    end
  end

  def test_live_gate_accepts_the_current_app_version_state_field
    snapshot = metadata_snapshot(state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    snapshot["version"]["attributes"]["appVersionState"] = snapshot["version"]["attributes"].delete("appStoreState")

    assert @validator.validate!(snapshot: snapshot, expected_build: 20_105, require_live: true)
  end
end
