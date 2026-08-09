# frozen_string_literal: true

require "test_helper"

class NotesTest < Minitest::Test
  Change = SequelAceRelease::GitRepository::Change

  def test_formats_release_body_in_required_order
    changes = [
      Change.new(sha: "a" * 40, title: "Add a feature", category: "added", pr_number: 10),
      Change.new(sha: "b" * 40, title: "Fix a crash", category: "fixed", pr_number: 11),
      Change.new(sha: "c" * 40, title: "Update CI", category: "infra", pr_number: 12)
    ]
    notes = SequelAceRelease::Notes.new(changes: changes)
    body = notes.github_body(
      app_store_notes: "A concise customer-facing update.",
      base_tag: "production/5.3.1-20104",
      head_ref: "d" * 40
    )

    assert body.start_with?("## App Store Release Notes\n\nA concise")
    assert_operator body.index("## What's Changed"), :>, body.index("## App Store Release Notes")
    assert_includes body, "### Added"
    assert_includes body, "### Fixed"
    assert_includes body, "### Infrastructure"
    assert_includes body, "/compare/production/5.3.1-20104...#{'d' * 40}"
    assert_equal "minor", notes.recommended_bump
  end

  def test_patch_is_default_without_added_changes
    change = Change.new(sha: "a" * 40, title: "Fix a crash", category: "fixed")
    assert_equal "patch", SequelAceRelease::Notes.new(changes: [change]).recommended_bump
  end

  def test_substantial_user_facing_change_recommends_minor
    change = Change.new(sha: "a" * 40, title: "Redesign the connection experience", category: "changed")
    assert_equal "minor", SequelAceRelease::Notes.new(changes: [change]).recommended_bump
  end
end
