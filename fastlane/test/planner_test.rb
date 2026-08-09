# frozen_string_literal: true

require "test_helper"

class PlannerTest < Minitest::Test
  FakeGit = Struct.new(:release_changes) do
    def sha(ref)
      ref.start_with?("production/") ? "b" * 40 : "a" * 40
    end

    def changes(base_ref:, head_ref:)
      raise unless base_ref == "production/5.3.1-20104" && head_ref == "main"

      release_changes
    end

    def latest_release_tag(channel:)
      raise unless channel == "production"

      "production/5.3.1-20104"
    end
  end

  FakeVersions = Struct.new(:value) do
    def current
      value
    end
  end

  def test_plan_recommends_minor_for_added_change_and_hashes_exact_notes
    changes = [SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Add connection diagnostics",
      category: "added",
      pr_number: 2500,
      author_name: "Contributor"
    )]
    planner = SequelAceRelease::Planner.new(
      git: FakeGit.new(changes),
      version_files: FakeVersions.new({ "version" => "5.3.1", "build" => 20_104 })
    )

    plan = planner.plan(
      channel: "production",
      target_version: "5.4.0",
      base_tag: "production/5.3.1-20104",
      main_ref: "main",
      app_store_notes: "New connection diagnostics.",
      observed_cloud_next_build: 20_105
    )

    assert_equal "minor", plan.fetch("recommended_bump")
    assert_equal "5.4.0", plan.fetch("recommended_version")
    assert_equal 20_105, plan.fetch("observed_production_cloud_next_build")
    assert_equal 20_105, plan.dig("approval", "observed_production_cloud_next_build")
    assert_equal "b" * 40, plan.dig("approval", "base_sha")
    assert_equal plan.fetch("release_notes_sha256"), plan.dig("approval", "release_notes_sha256")
    assert plan.fetch("github_release_body").start_with?("## App Store Release Notes")
    assert SequelAceRelease::Approval.from_hash(plan.fetch("approval")).verify!(plan.dig("approval", "sha256"))
  end

  def test_contributor_enrichment_changes_invalidate_the_approved_release_body
    change = SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Fix contributor-facing behavior",
      category: "fixed",
      pr_number: 2500,
      author_name: "Contributor"
    )
    enriched_github = Object.new
    enriched_github.define_singleton_method(:releases) { [] }
    enriched_github.define_singleton_method(:new_contributors) { |_numbers| { 2500 => "new-contributor" } }
    unavailable_github = Object.new
    unavailable_github.define_singleton_method(:releases) { [] }
    unavailable_github.define_singleton_method(:new_contributors) do |_numbers|
      raise SequelAceRelease::APIError, "contributor lookup unavailable"
    end
    arguments = {
      channel: "production",
      target_version: "5.3.2",
      base_tag: "production/5.3.1-20104",
      main_ref: "main",
      app_store_notes: "A focused fix.",
      observed_cloud_next_build: 20_105
    }
    versions = FakeVersions.new({ "version" => "5.3.1", "build" => 20_104 })
    approved = SequelAceRelease::Planner.new(
      git: FakeGit.new([change]), github: enriched_github, version_files: versions
    ).plan(**arguments)
    regenerated = SequelAceRelease::Planner.new(
      git: FakeGit.new([change]), github: unavailable_github, version_files: versions
    ).plan(**arguments)

    refute_equal approved.fetch("github_release_body"), regenerated.fetch("github_release_body")
    refute_equal approved.dig("approval", "sha256"), regenerated.dig("approval", "sha256")
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(regenerated.fetch("approval")).verify!(approved.dig("approval", "sha256"))
    end
  end

  def test_later_beta_compares_to_the_previous_beta_without_recommending_a_new_version
    change = SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Fix beta feedback",
      category: "fixed",
      pr_number: 2501,
      author_name: "Contributor"
    )
    git = Object.new
    git.define_singleton_method(:sha) { |ref| ref.start_with?("beta/") ? "b" * 40 : "a" * 40 }
    git.define_singleton_method(:changes) { |base_ref:, head_ref:| [change] }
    github = Object.new
    github.define_singleton_method(:releases) do
      [{
        "tag_name" => "beta/5.4.0-20105",
        "name" => "5.4.0 (20105) Beta 1",
        "prerelease" => true,
        "draft" => false,
        "published_at" => "2026-08-01T16:00:00Z"
      }]
    end
    github.define_singleton_method(:new_contributors) { |_numbers| {} }
    planner = SequelAceRelease::Planner.new(
      git: git,
      github: github,
      version_files: FakeVersions.new({ "version" => "5.4.0", "build" => 20_105 })
    )

    plan = planner.plan(
      channel: "beta",
      target_version: "5.4.0",
      main_ref: "main",
      observed_cloud_next_build: 20_106
    )
    assert_equal "beta/5.4.0-20105", plan.fetch("base_tag")
    assert_equal "same", plan.fetch("recommended_bump")
    assert_equal "5.4.0", plan.fetch("recommended_version")
    assert_equal 2, plan.fetch("iteration")
  end

  def test_production_target_cannot_reuse_or_regress_the_stable_version
    change = SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Fix a crash",
      category: "fixed"
    )
    planner = SequelAceRelease::Planner.new(
      git: FakeGit.new([change]),
      version_files: FakeVersions.new({ "version" => "5.3.1", "build" => 20_104 })
    )

    assert_raises(SequelAceRelease::ValidationError) do
      planner.plan(
        channel: "production",
        target_version: "5.3.1",
        base_tag: "production/5.3.1-20104",
        main_ref: "main"
      )
    end
  end
end
