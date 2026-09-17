# frozen_string_literal: true

require "test_helper"
require "yaml"
require "open3"

class WorkflowPlanTest < Minitest::Test
  include ReleaseTestHelpers

  class Git
    def sha(ref)
      ref.start_with?("production/") ? "b" * 40 : "a" * 40
    end

    def changes(**)
      [SequelAceRelease::GitRepository::Change.new(sha: "c" * 40, title: "Improve connections", category: "fixed")]
    end

    def ancestor?(*); true; end
  end

  def inputs
    { "channel" => "production", "version" => "5.3.2", "app_store_notes" => "- Improve connections.\n", "preview_only" => "false" }
  end

  def planner(beta: false)
    releases = [{ "tag_name" => "production/5.3.1-20104", "draft" => false, "prerelease" => false }]
    releases << { "tag_name" => "beta/5.3.2-20105", "prerelease" => true, "name" => "5.3.2 (20105) Beta 1" } if beta
    github = Object.new
    github.define_singleton_method(:releases) { releases }
    github.define_singleton_method(:new_contributors) { |_| {} }
    versions = Object.new
    versions.define_singleton_method(:current) { { "version" => "5.3.1", "build" => 20_104 } }
    SequelAceRelease::Planner.new(git: Git.new, github: github, version_files: versions)
  end

  def create(values = inputs, beta: false)
    SequelAceRelease::WorkflowPlan.new(planner: planner(beta: beta)).create(inputs: values, main_sha: "a" * 40)
  end

  def test_form_submission_generates_all_internal_approval_fields
    plan = create
    dispatch = plan.fetch("dispatch_inputs")
    assert_equal "start", dispatch.fetch("mode")
    assert_equal "RELEASE production 5.3.2", dispatch.fetch("confirmation")
    assert_equal "production/5.3.1-20104", dispatch.fetch("previous_tag")
    assert_equal "a" * 40, dispatch.fetch("expected_main_sha")
    assert_equal "- Improve connections.", Base64.strict_decode64(dispatch.fetch("app_store_notes_b64"))
    assert_equal plan.fetch("github_release_body"), Base64.strict_decode64(dispatch.fetch("github_release_body_b64"))
    assert SequelAceRelease::Approval.from_hash(plan.fetch("approval")).verify!(dispatch.fetch("approval_sha256"))
    refute plan.fetch("preview_only")
    refute dispatch.key?("build")
  end

  def test_later_beta_resolves_incremental_notes_and_cumulative_changelog_in_actions
    plan = create(inputs.merge("channel" => "beta"), beta: true)
    assert_equal "beta/5.3.2-20105", plan.fetch("base_tag")
    assert_equal "production/5.3.1-20104", plan.fetch("changelog_base_tag")
    assert_equal 2, plan.fetch("iteration")
  end

  def test_generated_body_is_data_and_reproduces_the_exact_approval_in_the_engine
    notes = "- Quotes: ' \" $HOME $(touch /tmp/not-executed)\n- Café\n"
    plan = create(inputs.merge("app_store_notes" => notes))
    assert_includes plan.fetch("github_release_body"), notes.strip
    dispatch = plan.fetch("dispatch_inputs")
    replay = planner.plan(
      channel: dispatch.fetch("channel"), target_version: dispatch.fetch("version"),
      base_tag: dispatch.fetch("previous_tag"), main_ref: dispatch.fetch("expected_main_sha"),
      app_store_notes: Base64.strict_decode64(dispatch.fetch("app_store_notes_b64")),
      github_release_body: Base64.strict_decode64(dispatch.fetch("github_release_body_b64"))
    )
    assert_equal dispatch.fetch("approval_sha256"), replay.fetch("approval").fetch("sha256")
    changed = replay.fetch("approval").merge("release_notes_sha256" => Digest::SHA256.hexdigest("changed"))
    assert_raises(SequelAceRelease::ValidationError) { SequelAceRelease::Approval.from_hash(changed).verify!(dispatch.fetch("approval_sha256")) }
  end

  def test_rejects_empty_or_oversized_notes_and_hidden_operational_inputs
    ["", "- " + "x" * 4000, "- text\0", "- Good\n# heading", "-", " | \n"].each do |notes|
      assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge("app_store_notes" => notes)) }
    end
    %w[previous_tag approval_sha256 recovery_tag build confirmation github_release_notes github_release_body_b64].each do |field|
      assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge(field => "override")) }
    end
    assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge("github_release_notes" => "x" * 46_000)) }
    assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge("github_release_notes" => "\0")) }
  end

  def test_plain_text_web_notes_and_multiline_notes_become_the_same_bullets
    expected = "- Fix SSH connections\n- Improve exports"
    ["Fix SSH connections | Improve exports", "Fix SSH connections\nImprove exports",
     "- Fix SSH connections\r\n- Improve exports", "  Fix SSH connections | - Improve exports  "].each do |notes|
      assert_equal expected, create(inputs.merge("app_store_notes" => notes)).fetch("app_store_notes")
    end
  end

  def test_optional_source_pin_defaults_to_dispatch_main_and_never_selects_stale_source
    ["", "a" * 40, "A" * 40].each do |sha|
      assert_equal "a" * 40, create(inputs.merge("expected_main_sha" => sha)).fetch("main_sha")
    end
    ["b" * 40, "main", "abc", nil, "a" * 40 + "\n"].each do |sha|
      assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge("expected_main_sha" => sha)) }
    end
  end

  def test_pasted_bullet_styles_normalize_without_doubled_markers
    ["- ", "* ", "+ ", "• ", "•", "●\t", "▪ ", "◦ ", "‣ ", "– ", "— ", "1. ", "2) ", "- - ", "- * "].each do |marker|
      plan = create(inputs.merge("app_store_notes" => "  #{marker}Fix SSH\r\n\n#{marker}Improve exports  "))
      notes = "- Fix SSH\n- Improve exports"
      assert_equal notes, plan.fetch("app_store_notes"), marker
      assert_equal notes, Base64.strict_decode64(plan.fetch("dispatch_inputs").fetch("app_store_notes_b64"))
      assert_includes plan.fetch("github_release_body"), notes
      replay = create(inputs.merge("app_store_notes" => notes))
      assert_equal replay.fetch("approval").fetch("sha256"), plan.fetch("approval").fetch("sha256")
    end
  end

  def test_note_content_is_preserved_and_empty_markers_are_rejected
    notes = "-1 is a valid value | C++ compatibility | 6.0.0 support | Café and 日本語"
    assert_equal "- -1 is a valid value\n- C++ compatibility\n- 6.0.0 support\n- Café and 日本語",
                 create(inputs.merge("app_store_notes" => notes)).fetch("app_store_notes")
    ["*", "•", "1.", "- -", "Good change | +", "- # Heading"].each do |bad|
      assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge("app_store_notes" => bad)) }
    end
  end

  def test_preview_is_optional_and_strictly_boolean
    assert create(inputs.merge("preview_only" => true)).fetch("preview_only")
    assert create(inputs.merge("preview_only" => "true")).fetch("preview_only")
    refute create(inputs.reject { |key, _| key == "preview_only" }).fetch("preview_only")
    assert_raises(SequelAceRelease::ValidationError) { create(inputs.merge("preview_only" => "yes")) }
  end

  def workflow(name)
    YAML.load_file(File.expand_path("../../.github/workflows/#{name}.yml", __dir__))
  end

  def events(data)
    data["on"] || data[true]
  end

  def test_public_form_reuses_the_same_revision_engine_without_a_second_approval
    form = workflow("release_deploy")
    engine = workflow("release")
    fields = events(form).fetch("workflow_dispatch").fetch("inputs")
    assert_equal SequelAceRelease::WorkflowPlan::INPUTS.sort, fields.keys.sort
    assert_equal false, fields.fetch("preview_only").fetch("default")
    assert_equal false, fields.fetch("expected_main_sha").fetch("required")
    assert_equal "", fields.fetch("expected_main_sha").fetch("default")
    assert_equal "New Sequel Ace release", form.fetch("name")
    assert_includes engine.fetch("name"), "advanced recovery only"
    wake_names = events(workflow("release_publish")).fetch("workflow_run").fetch("workflows")
    assert_includes wake_names, form.fetch("name")
    assert_includes wake_names, engine.fetch("name")
    refute form.key?("concurrency"), "caller must not deadlock the serialized engine"
    assert_equal({ "contents" => "read" }, form.dig("jobs", "plan", "permissions"))
    refute form.dig("jobs", "plan").key?("environment")
    deploy = form.dig("jobs", "deploy")
    assert_equal "./.github/workflows/release.yml", deploy.fetch("uses")
    assert_equal "${{ !inputs.preview_only }}", deploy.fetch("if")
    assert_equal ["deploy", "plan"], form.fetch("jobs").keys.sort
    schema = events(engine).fetch("workflow_call").fetch("inputs")
    assert_empty deploy.fetch("with").keys - schema.keys
    assert_empty schema.select { |_, value| value["required"] }.keys - deploy.fetch("with").keys
    assert_equal "sequel-ace-release", engine.fetch("concurrency").fetch("group")
    assert_equal "sequel-ace-release", engine.dig("jobs", "release", "environment")
    assert_equal engine.fetch("permissions"), deploy.fetch("permissions")
  end

  def test_precheckout_authorization_rejects_wrong_actor_ref_version_and_rerun_identity
    gate = workflow("release_deploy").dig("jobs", "plan", "steps").first.fetch("run")
    base = { "RELEASE_REF" => "refs/heads/main", "RELEASE_ACTOR" => "Jason-Morcos", "RELEASE_TRIGGERING_ACTOR" => "Jason-Morcos", "RELEASE_VERSION" => "6.0.1", "RELEASE_CHANNEL" => "production" }
    %w[Jason-Morcos Kaspik].product(%w[Jason-Morcos Kaspik]).each do |actor, rerunner|
      assert Open3.capture3(base.merge("RELEASE_ACTOR" => actor, "RELEASE_TRIGGERING_ACTOR" => rerunner), "bash", "-c", gate).last.success?
    end
    %w[intruder github-actions[bot] codex-pnw[bot] jason-morcos kaspik].each do |other|
      %w[RELEASE_ACTOR RELEASE_TRIGGERING_ACTOR].each do |field|
        refute Open3.capture3(base.merge(field => other), "bash", "-c", gate).last.success?
      end
    end
    [{ "RELEASE_REF" => "refs/heads/feature" }, { "RELEASE_ACTOR" => "github-actions[bot]" },
     { "RELEASE_TRIGGERING_ACTOR" => "intruder" }, { "RELEASE_VERSION" => "6.0.1; exit 0" },
     { "RELEASE_CHANNEL" => "anything" }].each do |override|
      refute Open3.capture3(base.merge(override), "bash", "-c", gate).last.success?
    end
  end

  def test_job_level_authorization_precedes_planning_and_engine_credentials
    human_guard = "(github.actor == 'Jason-Morcos' || github.actor == 'Kaspik') && " \
                  "(github.triggering_actor == 'Jason-Morcos' || github.triggering_actor == 'Kaspik')"
    assert_equal human_guard, workflow("release_deploy").dig("jobs", "plan", "if").strip
    engine = workflow("release").dig("jobs", "release", "if").gsub(/\s+/, " ").strip
    assert_equal "(#{human_guard}) || " \
                 "(github.actor == 'github-actions[bot]' && github.triggering_actor == 'github-actions[bot]' && " \
                 "inputs.mode == 'resume' && inputs.recovery_tag != '')", engine
  end
end
