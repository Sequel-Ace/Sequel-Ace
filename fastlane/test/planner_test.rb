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

    def parents(_ref)
      []
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
    assert_equal "production/5.3.1-20104", plan.fetch("changelog_base_tag")
    assert_equal "b" * 40, plan.dig("approval", "changelog_base_sha")
    assert_equal plan.fetch("release_notes_sha256"), plan.dig("approval", "release_notes_sha256")
    assert_equal plan.fetch("iteration"), plan.dig("approval", "release_iteration")
    assert plan.fetch("github_release_body").start_with?("## App Store Release Notes")
    assert SequelAceRelease::Approval.from_hash(plan.fetch("approval")).verify!(plan.dig("approval", "sha256"))
  end

  def test_merged_release_recovery_reuses_the_original_preparation_base_for_notes
    product_change = SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Fix release behavior",
      category: "fixed",
      pr_number: 2500,
      author_name: "Contributor"
    )
    release_change = SequelAceRelease::GitRepository::Change.new(
      sha: "d" * 40,
      title: "Prepare 5.3.2 (20105) release",
      category: "changed",
      pr_number: 2501,
      author_name: "sequel-ace-release[bot]"
    )
    git = Object.new
    git.define_singleton_method(:sha) do |ref|
      {
        "production/5.3.1-20104" => "b" * 40,
        "release-merge" => "d" * 40,
        "pre-release-main" => "a" * 40
      }.fetch(ref)
    end
    git.define_singleton_method(:parents) do |ref|
      raise unless ref == "release-merge"

      ["pre-release-main", "release-bot-commit"]
    end
    git.define_singleton_method(:changes) do |base_ref:, head_ref:|
      case [base_ref, head_ref]
      when ["pre-release-main", "release-merge"] then [release_change]
      when ["production/5.3.1-20104", "pre-release-main"] then [product_change]
      else raise "unexpected comparison #{base_ref}...#{head_ref}"
      end
    end
    planner = SequelAceRelease::Planner.new(
      git: git,
      version_files: FakeVersions.new({ "version" => "5.3.2", "build" => 20_105 })
    )

    plan = planner.plan(
      channel: "production",
      target_version: "5.3.2",
      base_tag: "production/5.3.1-20104",
      main_ref: "release-merge",
      app_store_notes: "A focused fix.",
      observed_cloud_next_build: 20_105
    )

    assert_equal "d" * 40, plan.fetch("main_sha")
    assert_equal "a" * 40, plan.fetch("release_notes_head_sha")
    assert_includes plan.fetch("github_release_body"), "Fix release behavior"
    assert_includes plan.fetch("github_release_body"), "production/5.3.1-20104...#{'a' * 40}"
    refute_includes plan.fetch("github_release_body"), "Prepare 5.3.2"
  end

  def test_a_new_prerelease_iteration_invalidates_the_approved_plan
    change = SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Fix release behavior",
      category: "fixed"
    )
    no_releases = Object.new
    no_releases.define_singleton_method(:releases) { [] }
    no_releases.define_singleton_method(:new_contributors) { |_numbers| {} }
    existing_candidate = Object.new
    existing_candidate.define_singleton_method(:releases) do
      [{
        "tag_name" => "production/5.3.2-20105",
        "name" => "5.3.2 (20105) - Release Candidate 1",
        "prerelease" => true,
        "draft" => false,
        "published_at" => "2026-08-09T18:00:00Z"
      }]
    end
    existing_candidate.define_singleton_method(:new_contributors) { |_numbers| {} }
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
      git: FakeGit.new([change]), github: no_releases, version_files: versions
    ).plan(**arguments)
    regenerated = SequelAceRelease::Planner.new(
      git: FakeGit.new([change]), github: existing_candidate, version_files: versions
    ).plan(**arguments)

    assert_equal 1, approved.fetch("iteration")
    assert_equal 2, regenerated.fetch("iteration")
    refute_equal approved.dig("approval", "sha256"), regenerated.dig("approval", "sha256")
    assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::Approval.from_hash(regenerated.fetch("approval")).verify!(approved.dig("approval", "sha256"))
    end
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
    git.define_singleton_method(:sha) do |ref|
      if ref.start_with?("beta/")
        "b" * 40
      elsif ref.start_with?("production/")
        "c" * 40
      else
        "a" * 40
      end
    end
    git.define_singleton_method(:changes) do |base_ref:, head_ref:|
      raise unless base_ref == "beta/5.4.0-20105" && head_ref == "main"

      [change]
    end
    git.define_singleton_method(:ancestor?) do |ancestor_ref, descendant_ref|
      raise unless descendant_ref == "beta/5.4.0-20105"

      ancestor_ref == "production/5.3.1-20104"
    end
    github = Object.new
    github.define_singleton_method(:releases) do
      [{
        "tag_name" => "beta/5.4.0-20105",
        "name" => "5.4.0 (20105) Beta 1",
        "prerelease" => true,
        "draft" => false,
        "published_at" => "2026-08-01T16:00:00Z"
      }, {
        "tag_name" => "production/5.3.1-20104",
        "name" => "5.3.1 (20104)",
        "prerelease" => false,
        "draft" => false,
        "published_at" => "2026-07-01T16:00:00Z"
      }, {
        "tag_name" => "production/5.3.2-20106",
        "name" => "5.3.2 (20106) - Release Candidate 1",
        "prerelease" => true,
        "draft" => false,
        "published_at" => "2026-07-15T16:00:00Z"
      }, {
        "tag_name" => "production/5.3.3-20107",
        "name" => "5.3.3 (20107)",
        "prerelease" => false,
        "draft" => false,
        "published_at" => "2026-08-02T16:00:00Z"
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
    assert_equal "b" * 40, plan.fetch("base_sha")
    assert_equal "production/5.3.1-20104", plan.fetch("changelog_base_tag")
    assert_equal "c" * 40, plan.fetch("changelog_base_sha")
    assert_equal "production/5.3.1-20104", plan.dig("approval", "changelog_base_tag")
    assert_includes plan.fetch("github_release_body"), "beta/5.4.0-20105...#{'a' * 40}"
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

  def test_malformed_explicit_base_tag_fails_with_a_clear_validation_error
    change = SequelAceRelease::GitRepository::Change.new(
      sha: "c" * 40,
      title: "Fix a crash",
      category: "fixed"
    )
    git = Object.new
    git.define_singleton_method(:sha) { |_ref| "a" * 40 }
    git.define_singleton_method(:changes) { |**_arguments| [change] }
    git.define_singleton_method(:parents) { |_ref| [] }
    planner = SequelAceRelease::Planner.new(
      git: git,
      version_files: FakeVersions.new({ "version" => "5.3.1", "build" => 20_104 })
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      planner.plan(
        channel: "production",
        base_tag: "production/not-a-release",
        main_ref: "main",
        observed_cloud_next_build: 20_105
      )
    end
    assert_includes error.message, "base tag production/not-a-release is malformed"
  end
end
