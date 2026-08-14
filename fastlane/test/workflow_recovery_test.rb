# frozen_string_literal: true

require "test_helper"

class WorkflowRecoveryTest < Minitest::Test
  def test_release_wait_uses_job_token_then_refreshes_app_tokens_for_mutations
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    wait_step = workflow.index("- name: Wait for exact-head release PR checks")
    merge_token_step = workflow.index("- name: Refresh release App token before merging")
    merge_step = workflow.index("- name: Recheck and merge the release PR")
    cleanup_token_step = workflow.index("- name: Refresh release App token for failure cleanup")
    cleanup_step = workflow.index("- name: Reconcile a failed release branch")

    assert wait_step
    assert merge_token_step
    assert merge_step
    assert cleanup_token_step
    assert cleanup_step
    assert_operator wait_step, :<, merge_token_step
    assert_operator merge_token_step, :<, merge_step
    assert_operator cleanup_token_step, :<, cleanup_step
    assert_includes workflow[wait_step...merge_token_step], "SA_GITHUB_TOKEN: ${{ github.token }}"
    assert_includes workflow[merge_step...cleanup_token_step], "SA_GITHUB_TOKEN: ${{ steps.merge_app_token.outputs.token }}"
    assert_includes workflow[cleanup_step..], "steps.cleanup_app_token.outputs.token || github.token"
  end

  def test_only_exact_release_mutations_request_workflows_write
    branch_permissions = [
      ["permission-actions", "read"],
      ["permission-checks", "read"],
      ["permission-contents", "write"],
      ["permission-pull-requests", "write"]
    ]
    cleanup_permissions = [
      ["permission-contents", "write"],
      ["permission-pull-requests", "write"]
    ]
    release_mutation_permissions = [
      ["permission-contents", "write"],
      ["permission-workflows", "write"]
    ]
    expected_permissions = {
      ".github/workflows/release.yml:Mint repository-scoped release App token" => branch_permissions,
      ".github/workflows/release.yml:Refresh release App token before merging" => branch_permissions,
      ".github/workflows/release.yml:Mint exact-target release tag token" => release_mutation_permissions,
      ".github/workflows/release.yml:Refresh release App token for failure cleanup" => cleanup_permissions,
      ".github/workflows/release.yml:Mint release mutation token for failure annotation" => release_mutation_permissions,
      ".github/workflows/release_alpha_retry.yml:Mint repository-scoped release App token" => [["permission-contents", "read"]],
      ".github/workflows/release_alpha_retry.yml:Mint release mutation token for failure annotation" => release_mutation_permissions,
      ".github/workflows/release_feasibility.yml:Mint a fresh release App token for the GitHub probe" => cleanup_permissions,
      ".github/workflows/release_feasibility.yml:Refresh release App token for probe cleanup" => cleanup_permissions,
      ".github/workflows/release_finalize.yml:Mint exact-target release mutation token" => release_mutation_permissions,
      ".github/workflows/release_publish.yml:Mint release mutation token for Cloud failure annotation" => release_mutation_permissions,
      ".github/workflows/release_publish.yml:Mint release mutation token for Alpha recovery annotation" => release_mutation_permissions,
      ".github/workflows/release_publish.yml:Mint release mutation token for terminal failure annotation" => release_mutation_permissions
    }
    observed_steps = []

    %w[
      release.yml
      release_alpha_retry.yml
      release_feasibility.yml
      release_finalize.yml
      release_publish.yml
    ].each do |filename|
      path = ".github/workflows/#{filename}"
      workflow = File.read(repo_path(path))
      token_steps = workflow.split(/(?=^      - name: )/).select do |step|
        step.include?("actions/create-github-app-token@")
      end
      refute_empty token_steps

      token_steps.each do |step|
        name = step.match(/^- name: (.+)$/)&.captures&.first ||
               step.match(/^      - name: (.+)$/)&.captures&.first
        refute_nil name
        label = "#{path}:#{name}"
        observed_steps << label
        permissions = step.lines.filter_map do |line|
          match = line.match(/^\s+(permission-[a-z-]+):\s+(\S+)\s*$/)
          [match[1], match[2]] if match
        end
        assert_equal expected_permissions.fetch(label).sort, permissions.sort,
                     "#{label} must request exactly its allowlisted App permissions"
      end
    end

    assert_equal expected_permissions.keys.sort, observed_steps.sort
  end

  def test_optional_release_annotations_cannot_block_durable_state
    release = File.read(repo_path(".github/workflows/release.yml"))
    release_token = release.split("- name: Mint release mutation token for failure annotation", 2).fetch(1)
                           .split("- name: Preserve an explanatory failed prerelease", 2).first
    release_failure = release.split("- name: Preserve an explanatory failed prerelease", 2).fetch(1)
    assert_includes release_token, "continue-on-error: true"
    assert_includes release_failure, '[[ -z "${RELEASE_MUTATION_TOKEN}" ]]'
    assert_operator release_failure.index("archive-release-to-ghcr.sh push"), :<,
                    release_failure.index('[[ -z "${RELEASE_MUTATION_TOKEN}" ]]')

    alpha = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    alpha_token = alpha.split("- name: Mint release mutation token for failure annotation", 2).fetch(1)
                       .split("- name: Document transient Alpha retry failure", 2).first
    alpha_failure = alpha.split("- name: Document transient Alpha retry failure", 2).fetch(1)
    assert_includes alpha_token, "continue-on-error: true"
    assert_includes alpha_failure, '[[ -z "${RELEASE_MUTATION_TOKEN}" ]]'

    publisher = File.read(repo_path(".github/workflows/release_publish.yml"))
    cloud_token = publisher.split("- name: Mint release mutation token for Cloud failure annotation", 2).fetch(1)
                           .split("- name: Authenticate and preserve the failed Cloud handoff", 2).first
    cloud_failure = publisher.split("- name: Authenticate and preserve the failed Cloud handoff", 2).fetch(1)
                             .split("  publish:", 2).first
    assert_includes cloud_token, "continue-on-error: true"
    assert_operator cloud_failure.index("archive-release-to-ghcr.sh push"), :<,
                    cloud_failure.index('[[ -z "${RELEASE_MUTATION_TOKEN}" ]]')
    assert_includes cloud_failure, "the optional GitHub annotation failed and will not block forward recovery"
    assert_operator cloud_failure.index("archive-release-to-ghcr.sh push"), :<,
                    cloud_failure.index("if ! (")

    alpha_archive = publisher.index("- name: Refresh the private archive with submission evidence")
    alpha_token_index = publisher.index("- name: Mint release mutation token for Alpha recovery annotation")
    alpha_token = publisher[alpha_token_index...publisher.index("- name: Append successful Alpha recovery evidence")]
    alpha_annotation = publisher.split("- name: Append successful Alpha recovery evidence", 2).fetch(1)
    assert_operator alpha_archive, :<, alpha_token_index
    assert_includes alpha_token, "continue-on-error: true"
    assert_includes alpha_annotation, '[[ -z "${RELEASE_MUTATION_TOKEN}" ]]'

    terminal_token = publisher.split("- name: Mint release mutation token for terminal failure annotation", 2).fetch(1)
                              .split("- name: Preserve terminal artifact-verification failure", 2).first
    terminal_failure = publisher.split("- name: Preserve terminal artifact-verification failure", 2).fetch(1)
                                .split("- name: Preserve retryable state", 2).first
    assert_includes terminal_token, "continue-on-error: true"
    assert_operator terminal_failure.index("archive-release-to-ghcr.sh push"), :<,
                    terminal_failure.index('[[ -z "${RELEASE_MUTATION_TOKEN}" ]]')

    exact_create_token = release.split("- name: Mint exact-target release tag token", 2).fetch(1)
                                .split("- name: Select the initial GitHub release publisher", 2).first
    finalizer = File.read(repo_path(".github/workflows/release_finalize.yml"))
    exact_finalize_token = finalizer.split("- name: Mint exact-target release mutation token", 2).fetch(1)
                                    .split("- name: Finalize only exact App Store-live releases", 2).first
    refute_includes exact_create_token, "continue-on-error: true"
    refute_includes exact_finalize_token, "continue-on-error: true"
  end

  def test_user_publisher_credential_is_scoped_only_to_initial_release_creation
    release = File.read(repo_path(".github/workflows/release.yml"))
    selector = release.split("- name: Select the initial GitHub release publisher", 2).fetch(1)
                      .split("- name: Create the tag-backed GitHub prerelease as Jason-Morcos", 2).first
    user_creation = release.split("- name: Create the tag-backed GitHub prerelease as Jason-Morcos", 2).fetch(1)
                           .split("- name: Create or recover the tag-backed GitHub prerelease with the release App", 2).first
    app_creation = release.split("- name: Create or recover the tag-backed GitHub prerelease with the release App", 2).fetch(1)
                          .split("- name: Record the exact GitHub prerelease identity", 2).first

    assert_equal 1, release.scan(/^\s+SA_RELEASE_GITHUB_PUBLISHER_TOKEN:/).length
    assert_equal 1, release.scan(/secrets\.SA_RELEASE_GITHUB_PUBLISHER_TOKEN/).length
    assert_includes user_creation,
                    'SA_RELEASE_GITHUB_PUBLISHER_TOKEN: ${{ secrets.SA_RELEASE_GITHUB_PUBLISHER_TOKEN }}'
    assert_includes user_creation, "if: steps.release_publisher.outputs.mode == 'user'"
    assert_includes user_creation, 'SA_GITHUB_TOKEN: ${{ steps.release_mutation_token.outputs.token }}'
    refute_includes selector, "SA_RELEASE_GITHUB_PUBLISHER_TOKEN"
    assert_includes selector, "github-release-publisher-mode"
    refute_includes app_creation, "SA_RELEASE_GITHUB_PUBLISHER_TOKEN"
    assert_includes app_creation, "steps.release_publisher.outputs.mode == 'app'"
    assert_includes app_creation, "steps.release_publisher.outputs.mode == 'existing'"
    assert_includes app_creation,
                    'SA_RELEASE_GITHUB_APP_CLIENT_ID: ${{ vars.SA_RELEASE_GITHUB_APP_CLIENT_ID }}'
    assert_includes app_creation,
                    'SA_RELEASE_GITHUB_APP_INSTALLATION_ID: ${{ steps.release_mutation_token.outputs.installation-id }}'
    assert_includes app_creation,
                    'SA_RELEASE_GITHUB_APP_SLUG: ${{ steps.release_mutation_token.outputs.app-slug }}'
    [user_creation, app_creation].each do |creation|
      %w[CHANNEL VERSION BUILD ITERATION TARGET_SHA].each do |name|
        assert_includes creation, "RELEASE_#{name}: " + '${{'
      end
      creation_run = creation.split("run: |", 2).fetch(1)
      refute_includes creation_run, '${{'
      %w[CHANNEL VERSION BUILD ITERATION TARGET_SHA].each do |name|
        assert_includes creation_run, '"${RELEASE_' + name + '}"'
      end
    end
    archive = release.split("- name: Durably archive the release identity before Cloud runs", 2).fetch(1)
                     .split("- name: Arm event-driven artifact publication for the exact handoff", 2).first
    assert_includes archive, "release-publisher.json"

    %w[release_alpha_retry.yml release_finalize.yml release_publish.yml release_feasibility.yml].each do |filename|
      refute_includes File.read(repo_path(".github/workflows/#{filename}")),
                      "SA_RELEASE_GITHUB_PUBLISHER_TOKEN"
    end
  end

  def test_artifact_wake_adapter_mints_only_an_exact_repository_variables_token
    {
      ".github/workflows/release.yml" => "Arm event-driven artifact publication for the exact handoff",
      ".github/workflows/release_alpha_retry.yml" => "Arm event-driven artifact publication for the exact Alpha retry",
      ".github/workflows/release_publish.yml" => "Clear only the exact settled handoff"
    }.each do |path, consumer_name|
      workflow = File.read(repo_path(path))
      consumer = workflow.split("- name: #{consumer_name}", 2).fetch(1)
                         .split(/^\s{6}- name: /, 2).first

      refute_includes workflow, "Mint release App token for artifact wake state"
      assert_includes consumer, "Scripts/release-artifact-wake-state.sh"
      assert_includes consumer, "GITHUB_REPOSITORY_ID: ${{ github.repository_id }}"
      assert_includes consumer, "SA_RELEASE_GITHUB_APP_CLIENT_ID"
      assert_includes consumer, "SA_RELEASE_GITHUB_APP_PRIVATE_KEY"
      refute_includes consumer, "GH_TOKEN:"
    end

    adapter = File.read(repo_path("Scripts/release-artifact-wake-state.sh"))
    assert_includes adapter, 'permissions:{actions_variables:"write"}'
    assert_includes adapter, 'repository_ids:[$id]'
    assert_includes adapter, '.permissions.actions_variables == "write"'
    assert_includes adapter, '.repositories | type == "array" and length == 1'
    assert_includes adapter, "--method DELETE installation/token"
  end

  def test_optional_release_annotations_cannot_recreate_a_missing_tag_from_main
    expected_targets = {
      "release.yml" => {
        events: [[:verify, "FAILED_TAG"], [:edit, "FAILED_TAG"], [:verify, "FAILED_TAG"]],
        source: 'RELEASE_COMMIT: ${{ steps.release_target.outputs.sha || steps.release_context.outputs.source_release_commit_sha }}'
      },
      "release_alpha_retry.yml" => {
        events: [[:verify, "BETA_TAG"], [:edit, "BETA_TAG"], [:verify, "BETA_TAG"]],
        source: 'RELEASE_COMMIT: ${{ inputs.expected_commit }}'
      },
      "release_publish.yml" => {
        events: [
          [:verify, "EXPECTED_TAG"], [:edit, "EXPECTED_TAG"], [:verify, "EXPECTED_TAG"],
          [:verify, "BETA_TAG"], [:edit, "BETA_TAG"], [:verify, "BETA_TAG"],
          [:verify, "FAILED_TAG"], [:edit, "FAILED_TAG"], [:verify, "FAILED_TAG"]
        ],
        source: 'RELEASE_COMMIT: ${{ needs.discover.outputs.commit }}'
      }
    }

    expected_targets.each do |filename, expected|
      workflow = File.read(repo_path(".github/workflows/#{filename}"))
      lines = workflow.lines
      edits = workflow.lines.grep(/gh release edit/)
      expected_edits = expected.fetch(:events).count { |event| event.first == :edit }

      assert_equal expected_edits, edits.length
      assert_equal Array.new(expected_edits, '--verify-tag --target "${RELEASE_COMMIT}"'),
                   edits.map { |line| line[/--verify-tag --target "\$\{RELEASE_COMMIT\}"/] }
      assert_equal expected_edits, workflow.scan(expected.fetch(:source)).length
      mutation_events = lines.each_with_index.filter_map do |line, index|
        if line.include?("github-verify-release-tag")
          tag = lines.fetch(index + 1)[/--tag "\$\{([A-Z_]+)\}"/, 1]
          assert_equal '--target-sha "${RELEASE_COMMIT}" >/dev/null', lines.fetch(index + 2).strip
          [:verify, tag]
        elsif line.include?("gh release edit")
          [:edit, line[/gh release edit "\$\{([A-Z_]+)\}"/, 1]]
        end
      end
      assert_equal expected.fetch(:events), mutation_events
    end
  end

  def test_cloud_target_is_reconciled_again_after_checks_and_before_merge_or_tag
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    wait_step = workflow.index("- name: Wait for exact-head release PR checks")
    fresh_token = workflow.index("- name: Refresh release App token before merging")
    reconcile_again = workflow.index("- name: Revalidate Production Cloud build immediately before merge or tag")
    merge_step = workflow.index("- name: Recheck and merge the release PR")
    tag_step = workflow.index("- name: Create the tag-backed GitHub prerelease")

    assert_operator wait_step, :<, fresh_token
    assert_operator fresh_token, :<, reconcile_again
    assert_operator reconcile_again, :<, merge_step
    assert_operator merge_step, :<, tag_step
    final_gate = workflow[reconcile_again...merge_step]
    tag_refresh = final_gate.index("git fetch --force --prune")
    base_revalidation = final_gate.index("refreshed_base_sha")
    changelog_base_revalidation = final_gate.index("refreshed_changelog_base_sha")
    reconciliation = final_gate.index("sa-release reconcile-build")
    assert_operator tag_refresh, :<, base_revalidation
    assert_operator base_revalidation, :<, changelog_base_revalidation
    assert_operator changelog_base_revalidation, :<, reconciliation
    assert_includes final_gate, "APPROVED_BASE_SHA"
    assert_includes final_gate, "APPROVED_CHANGELOG_BASE_SHA"
    assert_includes final_gate, "--expected-target-build"
    assert_includes final_gate, "mv pre-merge-reconciliation.json reconciliation.json"
  end

  def test_release_build_is_api_derived_without_a_ui_number_input
    workflow = File.read(repo_path(".github/workflows/release.yml"))

    refute_includes workflow, "production_cloud_next_build"
    refute_includes workflow, "--cloud-next-build"
    refute_includes workflow, "--observed-cloud-next-build"
    assert_equal 2, workflow.scan("sa-release reconcile-build").length
    assert_includes workflow, '--workflow-id "${{ vars.SA_PRODUCTION_CLOUD_WORKFLOW_ID }}"'
    assert_includes workflow, '"production_build_evidence" => reconciliation.fetch("production_build_evidence")'
  end

  def test_a_higher_assigned_number_dispatches_only_a_validated_forward_recovery
    release = File.read(repo_path(".github/workflows/release.yml"))
    publisher = File.read(repo_path(".github/workflows/release_publish.yml"))

    assert_includes publisher, 'failure_reason == \'cloud_build_number_advanced\''
    refute_includes publisher, 'failure_reason == \'cloud_build_number_regressed\' &&'
    recovery_job = publisher.split("  forward_build_recovery:", 2).fetch(1)
                            .split("  publish:", 2).first
    assert_includes recovery_job, "actions: write"
    assert_includes recovery_job, "validate-forward-recovery"
    assert_operator recovery_job.index("validate-forward-recovery"), :<,
                    recovery_job.index("actions/workflows/release.yml/dispatches")
    assert_includes recovery_job, '"mode" => "resume"'
    assert_includes recovery_job, '"recovery_tag" => recovery.fetch("predecessor_tag")'
    assert_includes recovery_job, '"approval_sha256" => approval.fetch("sha256")'
    recovery_validation = recovery_job.split("- name: Revalidate the durable failure and dispatch the next RC", 2).fetch(1)
    assert_includes recovery_validation, 'RELEASE_CHANNEL: ${{ needs.discover.outputs.channel }}'
    assert_includes recovery_validation, 'RELEASE_VERSION: ${{ needs.discover.outputs.version }}'
    run_body = recovery_validation.split("run: |", 2).fetch(1)
    refute_includes run_body, '${{ needs.discover.outputs.channel }}'
    refute_includes run_body, '${{ needs.discover.outputs.version }}'

    assert_includes release, 'RELEASE_ACTOR: ${{ github.actor }}'
    assert_includes release, '"${RELEASE_ACTOR}" == "github-actions[bot]"'
    assert_includes release, "validate-forward-recovery"
    assert_includes release, 'reconciliation.fetch("production_cloud_runs").find'
    assert_includes release, 'run.fetch("id") == recovery.fetch("cloud_run_id")'
    assert_includes release, 'exact_run.fetch("number") == recovery.fetch("cloud_assigned_build")'
    assert_includes release, '--base-sha "${{ steps.recovery.outputs.operational_main_sha }}"'
    assert_includes release, "forward_build_recovery"
  end

  def test_release_preparation_uses_the_approved_cumulative_changelog_base
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    preparation = workflow.split("- name: Prepare explicit release files", 2).fetch(1)
                          .split("- name: Create verified release bot commit and PR", 2).first

    assert_includes preparation, '--base-tag "${{ inputs.previous_tag }}"'
    assert_includes preparation, '--expected-base-sha "${{ steps.plan.outputs.base_sha }}"'
    assert_includes preparation, '--changelog-base-tag "${{ steps.plan.outputs.changelog_base_tag }}"'
    assert_includes preparation, '--expected-changelog-base-sha "${{ steps.plan.outputs.changelog_base_sha }}"'
  end

  def test_cancelled_release_runs_branch_and_prerelease_recovery
    release = File.read(repo_path(".github/workflows/release.yml"))
    cleanup_token = release[/\s+if: .*\n\s+id: cleanup_app_token/, 0]
    cleanup_step = release.split("- name: Reconcile a failed release branch", 2).fetch(1).lines.first(2).join
    prerelease_step = release.split("- name: Preserve an explanatory failed prerelease", 2).fetch(1)
                             .split("continue-on-error:", 2).first
    alpha = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    alpha_step = alpha.split("- name: Document transient Alpha retry failure without replacing the handoff", 2).fetch(1)
                      .split("continue-on-error:", 2).first

    assert_includes cleanup_token, "failure() || cancelled()"
    assert_includes cleanup_step, "failure() || cancelled()"
    assert_includes prerelease_step, "failure() || cancelled()"
    assert_includes alpha_step, "failure() || cancelled()"
  end

  def test_tag_only_recovery_treats_an_already_deleted_release_branch_as_absent
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    cleanup = workflow.split("- name: Delete a recovered merged release branch", 2).fetch(1)
                      .split("- name: Prepare explicit release files", 2).first

    assert_includes cleanup, "client.delete_branch(ENV.fetch(\"RELEASE_BRANCH\"), allow_absent: true)"
    refute_includes cleanup, "HTTP 404"
  end

  def test_mutating_workflows_authorize_the_rerun_initiator
    release = File.read(repo_path(".github/workflows/release.yml"))
    assert_operator release.scan("github.triggering_actor").length, :>=, 2
    assert_includes release, '--triggering-actor "${GUARD_TRIGGERING_ACTOR}"'
    assert_includes release, "Unauthorized release rerun initiator."

    {
      ".github/workflows/release_alpha_retry.yml" => "Unauthorized release rerun initiator.",
      ".github/workflows/release_feasibility.yml" => "Unauthorized feasibility rerun initiator.",
      ".github/workflows/release_finalize.yml" => "Unauthorized finalizer rerun initiator.",
      ".github/workflows/release_publish.yml" => "Unauthorized artifact-publisher rerun initiator."
    }.each do |path, rejection|
      workflow = File.read(repo_path(path))
      assert_includes workflow, "github.triggering_actor"
      assert_includes workflow, rejection
    end
  end

  def test_transient_workflow_evidence_cannot_pollute_release_commit_paths
    release = File.read(repo_path(".github/workflows/release.yml"))
    release_exclusion = release.index("- name: Exclude transient release evidence from git status")
    release_plan = release.index("- name: Decode and validate the approved plan")
    assert_operator release_exclusion, :<, release_plan
    assert_includes release[release_exclusion...release_plan], "/release-plan.json"
    assert_includes release[release_exclusion...release_plan], "/manifest.json"
    assert_includes release[release_exclusion...release_plan], "/release-publisher.json"
    overlap = release.split("- name: Refuse overlapping asynchronous release handoffs", 2).fetch(1)
                     .split("- name: Recheck release authorization with the tested guard", 2).first
    assert_includes overlap, 'prereleases_file="$(mktemp "${RUNNER_TEMP}/sequel-ace-existing-prereleases.XXXXXX")"'
    refute_includes overlap, "> existing-release-prereleases.txt"

    feasibility = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    feasibility_exclusion = feasibility.index("- name: Exclude transient feasibility evidence from git status")
    feasibility_probe = feasibility.index("- name: Create the verified GitHub App commit and disposable PR")
    assert_operator feasibility_exclusion, :<, feasibility_probe
    assert_includes feasibility[feasibility_exclusion...feasibility_probe], "/feasibility/"
  end

  def test_release_keeps_bundler_configuration_outside_the_tracked_worktree
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    external_config = workflow.index("- name: Keep Bundler configuration outside the tracked worktree")
    ruby_setup = workflow.index("- name: Set up Ruby and locked gems")
    config_check = workflow.index("- name: Verify Bundler left tracked configuration unchanged")
    preparation = workflow.index("- name: Prepare explicit release files")

    assert_operator external_config, :<, ruby_setup
    assert_operator ruby_setup, :<, config_check
    assert_operator config_check, :<, preparation

    setup = workflow[external_config...ruby_setup]
    assert_includes setup, 'mktemp -d "${RUNNER_TEMP}/sequel-ace-bundle-config.XXXXXX"'
    assert_includes setup, 'cp .bundle/config "${bundle_config_directory}/config"'
    assert_includes setup, %q(printf 'BUNDLE_APP_CONFIG=%s\n' "${bundle_config_directory}" >> "${GITHUB_ENV}")
    assert_includes workflow[config_check...preparation], "git diff --quiet -- .bundle/config"
  end

  def test_ambiguous_app_store_submission_is_polled_before_failure_recording
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    recovery = workflow.split("  recover_publish_failure:", 2).fetch(1)
    reconcile = recovery.index("reconcile-submission")
    record = recovery.index("- name: Preserve confirmed submission evidence")

    refute_nil reconcile
    refute_nil record
    assert_operator reconcile, :<, record
    assert_includes recovery[reconcile...record], "--wait-seconds 900"
    assert_includes recovery[reconcile...record], "--poll-interval 15"
    assert_includes recovery[record..], "--submission reconciled-submission.json"
    assert_includes recovery, "runs-on: ubuntu-latest"
  end

  def test_cloud_and_notarization_waits_are_split_from_mutating_handoffs
    release = File.read(repo_path(".github/workflows/release.yml"))
    alpha_retry = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    publisher = File.read(repo_path(".github/workflows/release_publish.yml"))

    [release, alpha_retry].each do |workflow|
      refute_includes workflow, "sa-release wait-cloud"
      refute_includes workflow, "sleep "
      assert_includes workflow, "Release Artifact Publisher"
      assert_includes workflow, "runs-on: ubuntu-latest"
      refute_includes workflow, "runs-on: macos-15"
    end
    assert_includes release, "Durably archive the release identity before Cloud runs"
    assert_includes alpha_retry, "Archive the exact Alpha retry handoff"
    assert_operator release.index("Durably archive the release identity before Cloud runs"), :<,
                    release.index("Arm event-driven artifact publication for the exact handoff")
    assert_operator alpha_retry.index("Archive the exact Alpha retry handoff"), :<,
                    alpha_retry.index("Arm event-driven artifact publication for the exact Alpha retry")
    assert_includes publisher, 'cron: "11,41 * * * *"'
    assert_includes publisher, "check_run:"
    assert_includes publisher, "types:\n      - completed"
    assert_includes publisher, "status: {}"
    assert_includes publisher, "workflow_run:"
    assert_includes publisher, "SA_RELEASE_PENDING_ARTIFACT_TAG"
    assert_includes publisher, "github.event.check_run.app.slug == 'xcode-cloud'"
    assert_includes publisher, "github.event.check_run.app.id == 117084"
    assert_includes publisher, "github.event_name == 'status'"
    assert_includes publisher, "runs-on: ubuntu-latest"
    assert_includes publisher, "sa-release cloud-status"
    refute_includes publisher, "sa-release wait-cloud"
    refute_includes publisher, "sleep "
    publish_job = publisher.split("  publish:", 2).fetch(1).split("  recover_publish_failure:", 2).first
    cloud_failure = publisher.split("  cloud_failure:", 2).fetch(1).split("  publish:", 2).first
    assert_includes publish_job, "if: needs.discover.outputs.action == 'publish'"
    refute_includes publish_job, "action == 'fail'"
    assert_includes publish_job, "runs-on: macos-15"
    assert_includes cloud_failure, "if: needs.discover.outputs.action == 'fail'"
    assert_includes cloud_failure, "runs-on: ubuntu-latest"
    assert_includes publisher, "selected_action=\"pending\""
    assert_includes publisher, "settle_artifact_wake_state:"
    assert_includes publisher, "release-artifact-wake-state.sh clear"
    production_gate = alpha_retry.index("- name: Resolve the existing exact Production build without waiting")
    retry_mutation = alpha_retry.index("- name: Reuse or start one Alpha-only Xcode Cloud retry")
    assert_operator production_gate, :<, retry_mutation
  end

  def test_new_releases_refuse_an_active_asynchronous_handoff
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    overlap = workflow.index("- name: Refuse overlapping asynchronous release handoffs")
    approval = workflow.index("- name: Recheck release authorization with the tested guard")
    gate = workflow[overlap...approval]

    assert_operator overlap, :<, approval
    assert_includes gate, "%w[cloud_running artifacts_verified archived submitted finalizing]"
    assert_includes gate, "%w[cloud_running artifacts_verified]"
    assert_includes gate, "ReleaseNaming.new"
    assert_includes gate, "still has an active asynchronous handoff"
    assert_includes gate, "ReleasePublisher.authorized?"
    assert_includes gate, "release_author"
    assert_includes gate, "has unreadable private handoff state; refusing to overlap it"
    refute_includes gate, "if Scripts/archive-release-to-ghcr.sh pull"
  end

  def test_publisher_uses_authenticated_xcode_checks_with_a_variable_gated_recovery_poll
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    discovery_job = workflow.split("  discover:", 2).fetch(1).split("  cloud_failure:", 2).first
    authorization = discovery_job.split("- name: Authorize the asynchronous publisher", 2).fetch(1)
                                 .split("- name: Check out immutable release tooling", 2).first
    candidate = discovery_job.split("- name: Inspect exact Cloud runs once", 2).fetch(1)

    assert_includes discovery_job, "github.event_name == 'workflow_dispatch'"
    assert_includes discovery_job, "startsWith(vars.SA_RELEASE_PENDING_ARTIFACT_TAG, 'production/')"
    assert_includes discovery_job, "startsWith(vars.SA_RELEASE_PENDING_ARTIFACT_TAG, 'beta/')"
    assert_includes discovery_job, "github.event.check_run.app.slug == 'xcode-cloud'"
    assert_includes discovery_job, "github.event.check_run.app.id == 117084"
    assert_includes discovery_job, "github.event_name == 'status'"
    assert_includes discovery_job, "github.event.context == 'Sequel Ace | Sequel Ace Release'"
    assert_includes discovery_job, "github.event.context == 'Sequel Ace Beta | Sequel Ace Beta'"
    assert_includes discovery_job, "checks: read"
    assert_includes authorization, '[[ "${SOURCE_CHECK_APP_ID}" == "117084" && "${SOURCE_CHECK_APP_SLUG}" == "xcode-cloud" ]]'
    assert_includes authorization, "Sequel Ace | Sequel Ace Release | Archive - macOS"
    assert_includes authorization, "Sequel Ace Beta | Sequel Ace Beta | Archive - macOS"
    assert_includes authorization, '[[ "${SOURCE_CHECK_STATUS}" == "completed" && -n "${SOURCE_CHECK_CONCLUSION}" ]]'
    assert_includes authorization, '[[ "${SOURCE_STATUS_STATE}" == "success" || "${SOURCE_STATUS_STATE}" == "failure" || "${SOURCE_STATUS_STATE}" == "error" ]]'
    assert_includes authorization, "/apps/1518036000/ci/builds/"
    assert_includes authorization, "/apps/1594104035/ci/builds/"
    assert_includes authorization, 'commits/${SOURCE_STATUS_SHA}/check-runs?per_page=100'
    assert_includes authorization, '.app.id == 117084 and .app.slug == \"xcode-cloud\"'
    assert_includes authorization, '[[ "${matching_check_count}" -ge 1 ]]'
    assert_includes candidate, 'release_tag="${REQUESTED_TAG:-${PENDING_TAG}}"'
    refute_includes candidate, "releases?per_page=100"
    refute_includes candidate, "while IFS="
  end

  def test_artifact_wake_state_is_cleared_only_after_durable_settlement
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    settlement = workflow.split("  settle_artifact_wake_state:", 2).fetch(1)

    assert_includes settlement, "needs.discover.outputs.action == 'settled'"
    assert_includes settlement, "needs.cloud_failure.result == 'success'"
    assert_includes settlement, "needs.discover.outputs.failure_reason != 'cloud_build_number_advanced'"
    assert_includes settlement, "needs.publish.result == 'success'"
    assert_includes settlement, "needs.recover_publish_failure.outputs.polling_needed == 'false'"
    assert_includes settlement, "permissions:\n      contents: read"
    assert_includes settlement, 'release-artifact-wake-state.sh clear "${SETTLED_TAG}"'
    refute_includes settlement, "needs.discover.outputs.action == 'pending'"

    recovery = workflow.split("  recover_publish_failure:", 2).fetch(1)
                       .split("  settle_artifact_wake_state:", 2).first
    assert_includes recovery, "polling_needed: ${{ steps.polling.outputs.polling_needed }}"
    assert_includes recovery, 'echo "polling_needed=false"'
    assert_includes recovery, 'echo "polling_needed=true"'
  end

  def test_forward_recovery_keeps_the_predecessor_armed_until_the_child_handoff_replaces_it
    release = File.read(repo_path(".github/workflows/release.yml"))
    arm = release.split("- name: Arm event-driven artifact publication for the exact handoff", 2).fetch(1)
                 .split("- name: Preserve a recoverable handoff", 2).first
    publisher = File.read(repo_path(".github/workflows/release_publish.yml"))
    settlement = publisher.split("  settle_artifact_wake_state:", 2).fetch(1)

    assert_includes arm, 'EXPECTED_PREDECESSOR_TAG: ${{ inputs.recovery_tag }}'
    assert_includes arm, 'arguments+=("${EXPECTED_PREDECESSOR_TAG}")'
    assert_includes arm, 'release-artifact-wake-state.sh "${arguments[@]}"'
    assert_includes settlement, "failure_reason != 'cloud_build_number_advanced'"
  end

  def test_unsuccessful_or_cancelled_wake_state_steps_preserve_the_durable_cloud_running_handoff
    release = File.read(repo_path(".github/workflows/release.yml"))
    release_arm = release.split("- name: Arm event-driven artifact publication for the exact handoff", 2).fetch(1)
                         .split("- name: Preserve a recoverable handoff", 2).first
    release_recovery = release.split("- name: Preserve a recoverable handoff when wake-state arming fails", 2).fetch(1)
                              .split("- name: Record asynchronous Cloud handoff", 2).first

    assert_includes release_arm, "id: artifact_wake"
    assert_includes release_recovery, "failure() || cancelled()"
    assert_includes release_recovery, "steps.initial_archive.outcome == 'success'"
    assert_includes release_recovery, "steps.artifact_wake.outcome != 'success'"
    assert_includes release_recovery, "remains \\`cloud_running\\`"
    assert_includes release, "steps.initial_archive.outcome != 'success' || steps.artifact_wake.outcome == 'success'"
    refute_includes release, "steps.artifact_wake.outcome == 'failure'"
    refute_includes release_recovery, "record-failure"

    alpha = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    alpha_arm = alpha.split("- name: Arm event-driven artifact publication for the exact Alpha retry", 2).fetch(1)
                     .split("- name: Preserve a recoverable Alpha handoff", 2).first
    alpha_recovery = alpha.split("- name: Preserve a recoverable Alpha handoff when wake-state arming fails", 2).fetch(1)
                          .split("- name: Record asynchronous Alpha retry handoff", 2).first
    assert_includes alpha, "id: retry_archive"
    assert_includes alpha_arm, "id: artifact_wake"
    assert_includes alpha_recovery, "failure() || cancelled()"
    assert_includes alpha_recovery, "steps.retry_archive.outcome == 'success'"
    assert_includes alpha_recovery, "steps.artifact_wake.outcome != 'success'"
    assert_includes alpha_recovery, "remains \\`cloud_running\\`"
    assert_includes alpha, "steps.retry_archive.outcome != 'success' || steps.artifact_wake.outcome == 'success'"
    refute_includes alpha, "steps.artifact_wake.outcome == 'failure'"
    refute_includes alpha_recovery, "record-failure"
  end

  def test_publisher_never_inspects_alpha_until_production_is_ready
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    discovery = workflow.split("- name: Inspect exact Cloud runs once", 2).fetch(1)
                        .split("  cloud_failure:", 2).first

    assert_includes discovery, '[[ "${channel}" == "beta" && "${production_readiness}" == "ready" ]]'
    assert_includes discovery, 'elif [[ "${production_readiness}" == "ready" && "${alpha_readiness}" == "failed" ]]'
    refute_includes discovery, '"${production_readiness}" != "failed"'
  end

  def test_publisher_writes_discovery_state_outside_the_pulled_archive
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    discovery = workflow.split("- name: Inspect exact Cloud runs once", 2).fetch(1)
                        .split("  cloud_failure:", 2).first

    assert_includes discovery, 'archive_directory="$(mktemp -d "${RUNNER_TEMP}/sequel-ace-publish-archive.XXXXXX")"'
    assert_includes discovery, 'state_directory="$(mktemp -d "${RUNNER_TEMP}/sequel-ace-publish-state.XXXXXX")"'
    assert_includes discovery, '--manifest "${archive_directory}/manifest.json"'
    assert_includes discovery, '--output "${state_directory}/context.json"'
    assert_includes discovery, '--output "${state_directory}/production-status.json"'
    assert_includes discovery, '--output "${state_directory}/alpha-status.json"'
    refute_includes discovery, '--output "${archive_directory}/'
  end

  def test_publisher_keeps_the_exact_wake_state_armed_when_its_archive_is_unreadable
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    discovery = workflow.split("- name: Inspect exact Cloud runs once", 2).fetch(1)
                        .split("  cloud_failure:", 2).first

    assert_includes discovery, 'if ! Scripts/archive-release-to-ghcr.sh pull "${archive_ref}" "${archive_directory}"'
    assert_includes discovery, "has no readable private handoff archive; recovery remains armed."
    refute_includes discovery, "it was skipped."
    refute_includes discovery, "unreadable=$((unreadable + 1))"
  end

  def test_publisher_settles_a_locally_terminal_wake_tag_but_fails_an_explicit_recovery
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    discovery = workflow.split("- name: Inspect exact Cloud runs once", 2).fetch(1)
                        .split("  cloud_failure:", 2).first
    local_gate = discovery.index('locally_eligible="$(bundle exec ruby -Ifastlane/lib -rsequel_ace_release')
    requested = discovery.index('if [[ -n "${REQUESTED_TAG}" ]]', local_gate)
    settled = discovery.index('echo "action=settled"', requested)
    terminal_exit = discovery.index("exit 0", settled)
    live_validation = discovery.index("bundle exec ruby fastlane/bin/sa-release validate-publish-handoff", terminal_exit)

    assert local_gate
    assert requested
    assert settled
    assert terminal_exit
    assert live_validation
    assert_operator local_gate, :<, requested
    assert_operator requested, :<, settled
    assert_operator settled, :<, terminal_exit
    assert_operator terminal_exit, :<, live_validation
    assert_includes discovery, "Requested release \${release_tag} is not eligible for artifact publication."
    assert_includes discovery, "recovery wake state can be cleared."
    assert_includes discovery, "PublishHandoff::ELIGIBLE_STATES"
    refute_includes discovery, "if ! bundle exec ruby fastlane/bin/sa-release validate-publish-handoff"
  end

  def test_publisher_shell_uses_environment_indirection_for_external_values
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    download = workflow.split("- name: Download exact Xcode Cloud artifacts", 2).fetch(1)
                       .split("- name: Verify, launch, quit, and package distributable apps", 2).first
    verify = workflow.split("- name: Verify, launch, quit, and package distributable apps", 2).fetch(1)
                     .split("- name: Attach checksum-idempotent verified public artifacts", 2).first
    attach = workflow.split("- name: Attach checksum-idempotent verified public artifacts", 2).fetch(1)
                     .split("- name: Archive verified artifacts privately", 2).first

    assert_includes download, '--run-id "${PRODUCTION_RUN_ID}"'
    assert_includes download, '--run-id "${ALPHA_RUN_ID}"'
    assert_includes verify, '--output-zip "artifacts/public/${PRODUCTION_ASSET}"'
    assert_includes verify, '--output-zip "artifacts/public/${ALPHA_ASSET}"'
    assert_includes attach, '--tag "${RELEASE_TAG}"'
    assert_includes attach, '--file "artifacts/public/${PRODUCTION_ASSET}"'
    assert_includes attach, '--file "artifacts/public/${ALPHA_ASSET}"'
    [download, verify, attach].each do |step|
      run_body = step.split("run: |", 2).fetch(1)
      refute_includes run_body, "${{"
    end
  end

  def test_transient_publisher_failures_leave_the_remote_handoff_retryable
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    recovery = workflow.split("  recover_publish_failure:", 2).fetch(1)
    terminal = recovery.split("- name: Preserve terminal artifact-verification failure", 2).fetch(1)
                       .split("- name: Preserve retryable state after a transient publisher failure", 2).first
    transient = recovery.split("- name: Preserve retryable state after a transient publisher failure", 2).fetch(1)

    assert_includes terminal, "sa-release record-failure"
    assert_includes terminal, "terminal_failure == 'artifact_verification'"
    assert_operator workflow.scan("--integrity-failure-marker terminal-artifact-verification-failure").length, :==, 2
    refute_includes transient, "sa-release record-failure"
    refute_includes transient, "archive-release-to-ghcr.sh push"
    assert_includes transient, "left unchanged so the next event or gated recovery check can retry safely"
  end

  def test_publisher_revalidates_every_exact_identity_before_artifact_writes
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    pull = workflow.index("- name: Pull and revalidate the exact private handoff")
    cloud = workflow.index("- name: Recheck exact Cloud readiness once")
    download = workflow.index("- name: Download exact Xcode Cloud artifacts")
    attach = workflow.index("- name: Attach checksum-idempotent verified public artifacts")
    archive = workflow.index("- name: Archive verified artifacts privately")
    submit = workflow.index("- name: Stage, verify, and submit the production App Store version")

    assert_operator pull, :<, cloud
    assert_operator cloud, :<, download
    assert_operator download, :<, attach
    assert_operator attach, :<, archive
    assert_operator archive, :<, submit
    assert_includes workflow[pull...cloud], "validate-publish-handoff"
    assert_includes workflow[pull...cloud], "--notes release-archive/app-store-notes.txt"
    assert_includes workflow[cloud...download], '--run-id "${PRODUCTION_RUN_ID}"'
    assert_includes workflow[cloud...download], '--run-id "${ALPHA_RUN_ID}"'
    upload = workflow[attach...archive]
    assert_equal 2, upload.scan("--manifest release-archive/manifest.json").length
    assert_equal 2, upload.scan("--notes release-archive/app-store-notes.txt").length
    submit_section = workflow[submit..].split("- name: Refresh the private archive with submission evidence", 2).first
    assert_includes submit_section, "SA_GITHUB_TOKEN: ${{ github.token }}"
  end

  def test_publisher_replaces_archive_artifacts_before_copying_verified_outputs
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    archive = workflow.split("- name: Archive verified artifacts privately", 2).fetch(1)
                      .split("- name: Stage, verify, and submit the production App Store version", 2).first
    remove = archive.index("/bin/rm -rf release-archive/artifacts")
    copy = archive.index("/usr/bin/ditto artifacts release-archive/artifacts")

    assert remove
    assert copy
    assert_operator remove, :<, copy
  end

  def test_publisher_reconciles_an_existing_exact_submission_before_retrying_mutation
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    submission = workflow.split("- name: Stage, verify, and submit the production App Store version", 2).fetch(1)
                         .split("- name: Refresh the private archive with submission evidence", 2).first
    reconcile = submission.index("reconcile-submission")
    mutate = submission.index("sa-release submit")

    assert_operator reconcile, :<, mutate
    assert_includes submission, 'if [[ "${already_submitted}" == "true" ]]'
    assert_includes submission, "pre-submit-reconciliation.json"
  end

  def test_cleanup_array_expansion_is_safe_under_macos_bash_nounset
    safe_expansion = '${reconcile_arguments[@]+"${reconcile_arguments[@]}"}'
    assert_includes File.read(repo_path(".github/workflows/release.yml")), safe_expansion
    assert_includes File.read(repo_path(".github/workflows/release_feasibility.yml")), safe_expansion

    assert system(
      "/bin/bash", "-c",
      'set -u; reconcile_arguments=(); printf "%s" ${reconcile_arguments[@]+"${reconcile_arguments[@]}"}'
    )
  end

  def test_finalizer_continues_when_an_archive_manifest_is_unreadable
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    assert_includes workflow, 'if ! state="$(ruby -rjson'
    assert_includes workflow, "private release archive has no readable manifest state"
    assert_includes workflow, "pending=$((pending + 1))"
    assert_includes workflow, "continue"
  end

  def test_finalizer_treats_archive_refresh_failures_as_pending
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))

    assert_includes workflow, 'if ! Scripts/archive-release-to-ghcr.sh push "${archive_ref}" "${archive_directory}" > "${finalizing_archive_evidence}"; then'
    assert_includes workflow, "could not archive finalization validation"
    assert_includes workflow, "GitHub is finalized but the live archive refresh failed"
    assert_operator workflow.scan("pending=$((pending + 1))").length, :>=, 6
    assert_operator workflow.scan("continue").length, :>=, 5
  end

  def test_finalizer_polls_every_six_hours_with_an_authorized_manual_fallback
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))

    assert_includes workflow, "schedule:"
    assert_includes workflow, 'cron: "17 */6 * * *"'
    refute_includes workflow, "repository_dispatch:"
    assert_includes workflow, "workflow_dispatch:"
    assert_includes workflow, "Optional exact production tag for authorized recovery"
    assert_includes workflow, 'REQUESTED_TAG: ${{ inputs.release_tag }}'
    assert_includes workflow, "Malformed requested production tag."
    assert_includes workflow, 'RELEASE_EVENT: ${{ github.event_name }}'
    assert_includes workflow, '"${RELEASE_EVENT}" == "workflow_dispatch"'
    assert_includes workflow, "Unauthorized scheduled-finalizer rerun initiator."
    assert_includes workflow, "scheduled six-hour poll"
    refute_includes workflow, "SA_WEBHOOK_GITHUB_APP_BOT"
    refute_includes workflow, "EVENT_APP_ID"
  end

  def test_manual_finalizer_can_repair_the_exact_post_transition_archive
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    discovery = workflow.split("  discover:", 2).fetch(1).split("  finalize:", 2).first
    execution = workflow.split("- name: Finalize only exact App Store-live releases", 2).fetch(1)

    assert_includes discovery, 'gh release view "${REQUESTED_TAG}"'
    assert_includes discovery, '.author.login == "sequel-ace-release-automation[bot]"'
    assert_includes discovery, '.author.login == "sequel-ace-releases[bot]"'
    assert_includes discovery, '.author.login == "Jason-Morcos"'
    refute_includes discovery, '.tagName == "production/5.4.0-20105"'
    refute_includes discovery, '.tag_name == "production/5.4.0-20105"'
    assert_includes discovery, '--json tagName,author,createdAt'
    assert_includes discovery, '(.createdAt | fromdateiso8601) as $created'
    assert_includes discovery, '(.author.login == "Jason-Morcos" and $build >= 20109 and $created < ("2027-08-14T00:00:00Z" | fromdateiso8601))'
    assert_includes discovery, '$build >= 20109 and $created >= ("2027-08-14T00:00:00Z" | fromdateiso8601)'
    assert_includes execution, 'printf \'%s\\n\' "${REQUESTED_TAG}" > production-candidates.txt'
    assert_includes execution, "GitHub is finalized but the live archive refresh failed"
    assert_includes execution, "--state finalizing"
    assert_includes execution, "--state live"
  end

  def test_scheduled_finalizer_skips_expensive_work_when_disabled_or_empty
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    discovery = workflow.split("  discover:", 2).fetch(1).split("  finalize:", 2).first
    finalizer = workflow.split("  finalize:", 2).fetch(1)

    assert_includes discovery, "runs-on: ubuntu-latest"
    assert_includes discovery, "environment: sequel-ace-release"
    assert_includes discovery, 'if [[ "${RELEASE_ENABLED}" != "true" ]]'
    assert_includes discovery, "the scheduled finalizer did no work"
    assert_includes discovery, "has_candidates=false"
    assert_includes discovery, "gh api --paginate"
    assert_includes discovery, 'repos/${GITHUB_REPOSITORY}/releases?per_page=100'
    assert_includes discovery, ".author.login"
    refute_includes discovery, "gh release list"
    refute_includes discovery, "--json tagName,isPrerelease,author,createdAt"
    assert_includes finalizer, "needs: discover"
    assert_includes finalizer, "needs.discover.outputs.enabled == 'true'"
    assert_includes finalizer, "needs.discover.outputs.has_candidates == 'true'"
    assert_includes finalizer, "Verify Production App Store Connect access"
  end

  def test_finalizer_executes_the_immutable_event_revision
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    checkout = workflow.split("- name: Check out release tooling", 2).fetch(1)
                       .split("- name: Set up Ruby and locked gems", 2).first

    assert_includes checkout, 'ref: ${{ github.sha }}'
    refute_includes checkout, "ref: main"
  end

  def test_release_checkout_is_preceded_by_a_complete_sha_ancestry_proof
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    authorization = workflow.index("- name: Enforce release authorization")
    ancestry = workflow.index("- name: Prove the frozen release SHA is on dispatch main")
    app_token = workflow.index("- name: Mint repository-scoped release App token")
    checkout = workflow.index("- name: Check out immutable dispatch tooling")
    proof = workflow[ancestry...app_token]

    assert_operator authorization, :<, ancestry
    assert_operator ancestry, :<, app_token
    assert_operator app_token, :<, checkout
    assert_includes workflow[authorization...ancestry], '[[ "${EXPECTED_SHA}" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]'
    assert_includes proof, '/compare/${EXPECTED_SHA}...${DISPATCH_SHA}'
    assert_includes proof, '"${comparison_status}" == "identical" || "${comparison_status}" == "ahead"'
  end

  def test_exact_resume_executes_trusted_current_tooling_but_keeps_the_release_plan_frozen
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    checkout = workflow.split("- name: Check out immutable dispatch tooling", 2).fetch(1)
                       .split("- name: Exclude transient release evidence from git status", 2).first
    plan = workflow.split("- name: Decode and validate the approved plan", 2).fetch(1)
                   .split("- name: Reconcile the authoritative Production Cloud build", 2).first

    assert_includes checkout, 'ref: ${{ github.sha }}'
    refute_includes checkout, 'ref: ${{ inputs.expected_main_sha }}'
    assert_includes plan, '--main-ref "${{ inputs.expected_main_sha }}"'
  end

  def test_release_workflows_use_commit_and_checksum_pinned_oras
    action = "oras-project/setup-oras@1d808f7d7f6995cc68b7bf507bfe5c5446e1dc9d"
    arm64_checksum = "f33fc12753c54172b0d0d19eaa0318d3f90fe9b094d96e8b259c881713c92e1c"
    amd64_checksum = "aeb684d8c24c18dce28fd1f7326636e4782b573108e244a93d4b1c4a5ec50f48"

    linux_checksum = "9ce999f8d2de03fc03968b29d743077a58783e545e5eaa53917ca177352d0e59"
    %w[release.yml release_alpha_retry.yml release_finalize.yml].each do |filename|
      workflow = File.read(repo_path(".github/workflows/#{filename}"))

      assert_equal 1, workflow.scan(action).length
      assert_includes workflow, "oras_1.3.3_linux_amd64.tar.gz"
      assert_includes workflow, linux_checksum
      refute_includes workflow, "oras_1.3.3_darwin_"
      refute_includes workflow, "brew install oras"
    end

    feasibility = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    assert_equal 2, feasibility.scan(action).length
    assert_includes feasibility, "oras_1.3.3_darwin_arm64.tar.gz"
    assert_includes feasibility, arm64_checksum
    assert_includes feasibility, "oras_1.3.3_darwin_amd64.tar.gz"
    assert_includes feasibility, amd64_checksum
    refute_includes feasibility, "brew install oras"

    publisher = File.read(repo_path(".github/workflows/release_publish.yml"))
    assert_equal 6, publisher.scan(action).length
    assert_includes publisher, "oras_1.3.3_linux_amd64.tar.gz"
    assert_includes publisher, linux_checksum
    assert_includes publisher, "oras_1.3.3_darwin_arm64.tar.gz"
    assert_includes publisher, arm64_checksum
    assert_includes publisher, "oras_1.3.3_darwin_amd64.tar.gz"
    assert_includes publisher, amd64_checksum
    refute_includes publisher, "brew install oras"
  end

  def test_publisher_executes_the_immutable_event_revision
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    assert_equal 6, workflow.scan('ref: ${{ github.sha }}').length
    refute_includes workflow, "ref: main"
    assert_includes workflow, 'SOURCE_HEAD_BRANCH: ${{ github.event.workflow_run.head_branch }}'
    assert_includes workflow, '[[ "${SOURCE_HEAD_BRANCH}" == "main" ]]'
    assert_includes workflow, 'SOURCE_WORKFLOW_PATH: ${{ github.event.workflow_run.path }}'
    assert_includes workflow, '"${SOURCE_WORKFLOW_PATH}" == ".github/workflows/release.yml"'
    assert_includes workflow, '"${SOURCE_WORKFLOW_PATH}" == ".github/workflows/release_alpha_retry.yml"'
    refute_includes workflow, "github.event.workflow_run.name"
    refute_includes workflow, 'SOURCE_WORKFLOW: ${{'
  end

  def test_supporting_release_workflows_execute_the_dispatch_revision
    %w[release_alpha_retry.yml release_feasibility.yml].each do |filename|
      workflow = File.read(repo_path(".github/workflows/#{filename}"))
      checkout = workflow.split("- name: Check out release tooling", 2).fetch(1)
                         .split("- name: Set up Ruby and locked gems", 2).first

      assert_includes checkout, 'ref: ${{ github.sha }}'
      refute_includes checkout, "ref: main"
    end
  end

  def test_apple_and_archive_credentials_are_scoped_to_consuming_steps
    release = File.read(repo_path(".github/workflows/release.yml"))
    release_job_env = release.split("environment: sequel-ace-release", 2).fetch(1)
                             .split("steps:", 2).first
    refute_includes release_job_env, "SA_ASC_KEY_ID"
    refute_includes release_job_env, "SA_ASC_PRIVATE_KEY"
    assert_includes release_job_env, 'SA_ASC_REQUIRE_ISSUER: "1"'

    reconcile = release.split("- name: Reconcile the authoritative Production Cloud build", 2).fetch(1)
                       .split("- name: Create the initial release manifest", 2).first
    assert_includes reconcile, 'SA_ASC_KEY_ID: ${{ secrets.SA_ASC_KEY_ID }}'
    assert_includes reconcile, 'SA_ASC_PRIVATE_KEY: ${{ secrets.SA_ASC_PRIVATE_KEY }}'

    finalizer = File.read(repo_path(".github/workflows/release_finalize.yml"))
    finalizer_job = finalizer.split("  finalize:", 2).fetch(1)
    finalizer_job_env = finalizer_job.split("environment: sequel-ace-release", 2).fetch(1)
                                     .split("steps:", 2).first
    refute_includes finalizer_job_env, "SA_ASC_KEY_ID"
    refute_includes finalizer_job_env, "SA_ASC_PRIVATE_KEY"
    refute_includes finalizer_job_env, "GHCR_TOKEN"
    refute_includes finalizer_job_env, "SA_GITHUB_TOKEN"
    assert_includes finalizer_job_env, 'SA_ASC_REQUIRE_ISSUER: "1"'

    access = finalizer.split("- name: Verify Production App Store Connect access", 2).fetch(1)
                      .split("- name: Mint exact-target release mutation token", 2).first
    assert_includes access, 'SA_ASC_KEY_ID: ${{ secrets.SA_ASC_KEY_ID }}'
    assert_includes access, 'SA_ASC_PRIVATE_KEY: ${{ secrets.SA_ASC_PRIVATE_KEY }}'

    finalize = finalizer.split("- name: Finalize only exact App Store-live releases", 2).fetch(1)
    assert_includes finalize, 'GHCR_TOKEN: ${{ github.token }}'
    github_token_assignments = finalize.scan(/^\s+SA_GITHUB_TOKEN:\s+(.+)$/).flatten
    assert_equal ['${{ steps.release_mutation_token.outputs.token }}'], github_token_assignments
    assert_includes finalize, 'SA_ASC_PRIVATE_KEY: ${{ secrets.SA_ASC_PRIVATE_KEY }}'

    %w[release_alpha_retry.yml release_feasibility.yml].each do |filename|
      workflow = File.read(repo_path(".github/workflows/#{filename}"))
      job_env = workflow.split("environment: sequel-ace-release", 2).fetch(1)
                        .split("steps:", 2).first

      refute_includes job_env, "SA_ASC_KEY_ID"
      refute_includes job_env, "SA_ASC_PRIVATE_KEY"
      refute_includes job_env, "GHCR_TOKEN"
      assert_includes job_env, 'SA_ASC_REQUIRE_ISSUER: "1"'
    end
  end

  def test_finalizer_discovers_only_production_prereleases
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    discovery = workflow.split("  discover:", 2).fetch(1).split("  finalize:", 2).first
    execution = workflow.split("- name: Finalize only exact App Store-live releases", 2).fetch(1)

    discovery_listing = discovery.index("gh api --paginate")
    discovery_prerelease_filter = discovery.index(".prerelease == true")
    discovery_production_filter = discovery.index('.tag_name | test("^production/')
    assert discovery_listing
    assert discovery_prerelease_filter
    assert discovery_production_filter
    assert_operator discovery_listing, :<, discovery_prerelease_filter
    assert_operator discovery_prerelease_filter, :<, discovery_production_filter
    assert_includes discovery, ".draft == false"

    execution_listing = execution.index("gh api --paginate")
    execution_prerelease_filter = execution.index(".prerelease == true")
    execution_production_filter = execution.index('.tag_name | test("^production/')
    assert execution_listing
    assert execution_prerelease_filter
    assert execution_production_filter
    assert_operator execution_listing, :<, execution_prerelease_filter
    assert_operator execution_prerelease_filter, :<, execution_production_filter
    assert_includes execution, ".draft == false"
    assert_includes execution, ".author.login"
    assert_includes execution, 'repos/${GITHUB_REPOSITORY}/releases?per_page=100'
    refute_includes execution, "gh release list"
    assert_operator execution_production_filter, :<, execution.index("--validate-only")
    refute_includes workflow, "resolve-app-store-version"
  end

  def test_pr_jobs_do_not_persist_the_checkout_token
    workflow = File.read(repo_path(".github/workflows/ci_pr_tests.yml"))
    assert_equal 2, workflow.scan("persist-credentials: false").length
  end

  def test_fastlane_app_store_mutations_require_the_release_gate
    fastfile = File.read(repo_path("fastlane/Fastfile"))
    stage_lane = fastfile.split("lane :stage_app_store_release", 2).fetch(1)
                         .split("lane :submit_app_store_release", 2).first
    submit_lane = fastfile.split("lane :submit_app_store_release", 2).fetch(1)
                          .split("lane :generate_changelog_locally", 2).first
    workflow = File.read(repo_path(".github/workflows/release.yml"))

    assert_includes stage_lane, "require_release_automation_enabled!"
    assert_includes submit_lane, "require_release_automation_enabled!"
    assert_includes fastfile, 'ENV["SA_ASC_REQUIRE_ISSUER"] == "1"'
    assert_includes fastfile, "SA_ASC_ISSUER_ID is required for the configured Team API key"
    assert_includes workflow, "SA_RELEASE_AUTOMATION_ENABLED: ${{ vars.SA_RELEASE_AUTOMATION_ENABLED }}"
  end

  def test_fastlane_prepare_adapter_passes_both_approved_bases
    fastfile = File.read(repo_path("fastlane/Fastfile"))
    prepare_lane = fastfile.split("lane :prepare_release_files", 2).fetch(1)
                           .split("lane :stage_app_store_release", 2).first

    assert_includes prepare_lane, '"--expected-base-sha", expected_base_sha'
    assert_includes prepare_lane, '"--changelog-base-tag", changelog_base_tag'
    assert_includes prepare_lane, '"--expected-changelog-base-sha", expected_changelog_base_sha'
  end

  def test_finalizer_archives_live_validation_before_the_public_transition
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    validation = workflow.index("--validate-only")
    finalizing = workflow.index("--state finalizing")
    archive = workflow.index('Scripts/archive-release-to-ghcr.sh push "${archive_ref}"')
    public_transition = workflow.index('--output "${state_directory}/finalization.json"')
    live = workflow.index("--state live")

    assert validation
    assert finalizing
    assert archive
    assert public_transition
    assert live
    assert_operator validation, :<, finalizing
    assert_operator finalizing, :<, archive
    assert_operator validation, :<, archive
    assert_operator archive, :<, public_transition
    assert_operator public_transition, :<, live
  end

  def test_finalizer_keeps_generated_state_outside_the_pulled_archive
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    execution = workflow.split("- name: Finalize only exact App Store-live releases", 2).fetch(1)

    assert_includes execution, 'archive_directory="$(mktemp -d "${RUNNER_TEMP}/sequel-ace-finalize-archive.XXXXXX")"'
    assert_includes execution, 'state_directory="$(mktemp -d "${RUNNER_TEMP}/sequel-ace-finalize-state.XXXXXX")"'
    assert_includes execution, '--manifest "${archive_directory}/manifest.json"'
    assert_includes execution, '--output "${state_directory}/finalization-validation.json"'
    assert_includes execution, '--output "${state_directory}/finalization.json"'
    assert_includes execution, '"${state_directory}/finalization-evidence.json" "${archive_directory}/"'
    refute_includes execution, '--output "${archive_directory}/'
  end

  def test_feasibility_wait_and_cleanup_do_not_reuse_the_probe_app_token
    workflow = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    create_token = workflow.index("- name: Mint a fresh release App token for the GitHub probe")
    create_probe = workflow.index("- name: Create the verified GitHub App commit and disposable PR")
    wait_checks = workflow.index("- name: Wait for exact-head feasibility PR checks")
    cleanup_token = workflow.index("- name: Refresh release App token for probe cleanup")
    cleanup_probe = workflow.index("- name: Close and delete only the exact feasibility probe")

    assert_operator create_token, :<, create_probe
    assert_operator create_probe, :<, wait_checks
    assert_operator wait_checks, :<, cleanup_token
    assert_operator cleanup_token, :<, cleanup_probe
    assert_includes workflow[wait_checks...cleanup_token], "SA_GITHUB_TOKEN: ${{ github.token }}"
    assert_includes workflow[cleanup_probe..], "steps.probe_cleanup_token.outputs.token || github.token"
  end

  def test_feasibility_fails_closed_unless_the_exact_ghcr_probe_version_is_deleted_via_rest
    workflow = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    probe = workflow.split("- name: Prove private GHCR round trip and visibility", 2).fetch(1)
                    .split("- name: Delete the exact GHCR feasibility probe", 2).first
    cleanup = workflow.split("- name: Delete the exact GHCR feasibility probe", 2).fetch(1)
                      .split("- name: Confirm publishing remains disabled after all gates pass", 2).first
    branch_marker = 'if [[ "${package_version_count}" -eq 1 ]]; then'
    snapshot_index = cleanup.index('package_versions_file="$(mktemp')
    initial_inventory_index = cleanup.index('gh api --paginate "${package_endpoint}/versions?per_page=100"', snapshot_index)
    branch_index = cleanup.index(branch_marker)
    readback_index = cleanup.index('package_readback_headers="$(gh api --include --silent "${package_endpoint}" 2>&1)"')

    refute_nil snapshot_index
    refute_nil initial_inventory_index
    refute_nil branch_index
    refute_nil readback_index
    assert_operator snapshot_index, :<, initial_inventory_index
    assert_operator initial_inventory_index, :<, branch_index
    assert_operator branch_index, :<, readback_index

    deletion_branches = cleanup[branch_index...readback_index]
    sole_version_branch, version_branch_with_end = deletion_branches.split("\n          else\n", 2)
    version_branch = version_branch_with_end.split("\n          fi\n", 2).first
    delete_targets = lambda do |branch|
      branch.lines
            .map(&:strip)
            .select { |line| line.start_with?('"${package_endpoint}') }
            .map { |line| line.sub(/\s+\\\z/, "") }
    end

    assert_equal ['"${package_endpoint}"'], delete_targets.call(sole_version_branch)
    assert_equal ['"${package_endpoint}/versions/${probe_version_id}"'], delete_targets.call(version_branch)
    assert_operator sole_version_branch.index('gh api --paginate "${package_endpoint}/versions?per_page=100"'),
                    :<,
                    sole_version_branch.index("gh api --method DELETE")

    assert_includes probe, "id: ghcr_probe"
    refute_includes probe, "oras manifest delete"
    assert_includes cleanup, "if: ${{ always() && steps.ghcr_probe.outcome != 'skipped' }}"
    assert_includes cleanup, 'probe_ref="${GHCR_REPOSITORY}:feasibility-${GITHUB_RUN_ID}"'
    assert_includes cleanup, 'probe_tag="feasibility-${GITHUB_RUN_ID}"'
    assert_includes cleanup, 'package_endpoint="orgs/Sequel-Ace/packages/container/${package_name}"'
    assert_includes cleanup, 'package_versions_file="$(mktemp "${RUNNER_TEMP}/sequel-ace-feasibility-package-versions.json.XXXXXX")"'
    assert_includes cleanup, "| jq -sc 'sort_by(.id)'"
    assert_includes cleanup, %q!package_version_count="$(jq -r 'length' "${package_versions_file}")"!
    assert_includes cleanup, "probe_version_rows=\"$("
    assert_includes cleanup, "Expected exactly one GHCR package version for the feasibility probe tag."
    assert_includes cleanup, "IFS=$'\\t' read -r probe_version_id probe_version_tags"
    assert_includes cleanup, '"${probe_version_tags}" == "${probe_tag}"'
    assert_includes cleanup, '"${package_version_count}" -eq 1'
    assert_includes cleanup, 'confirmed_versions_file="$(mktemp "${RUNNER_TEMP}/sequel-ace-feasibility-confirmed-versions.json.XXXXXX")"'
    refute_includes cleanup, "XXXXXX.json"
    assert_includes cleanup, 'cmp -s "${package_versions_file}" "${confirmed_versions_file}"'
    assert_includes cleanup, "GHCR package versions changed before whole-package probe cleanup."
    assert_includes cleanup, 'deleted_entire_package=1'
    assert_includes cleanup, 'package_readback_headers="$(gh api --include --silent "${package_endpoint}" 2>&1)"'
    assert_includes cleanup, %q!package_readback_status="$(awk 'NR == 1 { print $2 }' <<< "${package_readback_headers}")"!
    assert_includes cleanup, '"${deleted_entire_package}" -eq 1 && "${package_readback_exit}" -ne 0 && "${package_readback_status}" == "404"'
    assert_includes cleanup, '"${deleted_entire_package}" -eq 0 && "${package_readback_exit}" -eq 0 && "${package_readback_status}" == "200"'
    assert_includes cleanup, 'gh api --paginate "${package_endpoint}/versions?per_page=100"'
    assert_includes cleanup, '.[] | select(any(.metadata.container.tags[]?; . == \"${probe_tag}\")) | .id'
    assert_includes cleanup, 'remaining_probe_versions=""'
    assert_includes cleanup, 'Unexpected GHCR package read-back after probe cleanup (whole_package=${deleted_entire_package}, status=${package_readback_status:-unavailable}).'
    refute_includes cleanup, "--slurp"
    assert_includes cleanup, '[[ -z "${remaining_probe_versions}" ]]'
    refute_includes cleanup, "oras manifest delete"
  end

  def test_feasibility_binds_a_reusable_alpha_run_to_an_explicit_ancestor_sha
    workflow = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    source_input = workflow.split("      alpha_source_sha:", 2).fetch(1)
                           .split("\n\npermissions:", 2).first
    artifact_step = workflow.split("- name: Download and verify the real Alpha notarization artifact", 2).fetch(1)
                            .split("- name: Mint a fresh release App token for the GitHub probe", 2).first

    assert_includes source_input, "required: true"
    assert_includes source_input, "type: string"
    assert_includes workflow, 'ALPHA_BUILD_RUN_ID: ${{ inputs.alpha_build_run_id }}'
    assert_includes workflow, 'ALPHA_SOURCE_SHA: ${{ inputs.alpha_source_sha }}'
    assert_includes workflow, 'SA_ALPHA_WORKFLOW_ID: ${{ vars.SA_ALPHA_CLOUD_WORKFLOW_ID }}'
    assert_includes workflow, '[[ "${ALPHA_SOURCE_SHA}" =~ ^[0-9a-fA-F]{40}$ ]]'
    assert_includes workflow, 'canonical_alpha_source_sha="$(git rev-parse --verify "${ALPHA_SOURCE_SHA}^{commit}")"'
    assert_includes workflow, '[[ "${canonical_alpha_source_sha}" =~ ^[0-9a-f]{40}$ ]]'
    assert_includes workflow, 'git merge-base --is-ancestor "${canonical_alpha_source_sha}" "${current_sha}"'
    assert_includes workflow, 'printf \'ALPHA_SOURCE_SHA=%s\\n\' "${canonical_alpha_source_sha}" >> "${GITHUB_ENV}"'
    assert_includes artifact_step, 'run["source_commit"] == ARGV.fetch(2)'
    assert_includes artifact_step, '"${ALPHA_BUILD_RUN_ID}" "${SA_ALPHA_WORKFLOW_ID}" "${ALPHA_SOURCE_SHA}"'
    assert_includes artifact_step, '--run-id "${ALPHA_BUILD_RUN_ID}"'
    assert_includes workflow, "Alpha run does not match the pinned source commit"
    refute_includes artifact_step, '${{ vars.SA_ALPHA_CLOUD_WORKFLOW_ID }}'
    refute_includes artifact_step, '--run-id "${{ inputs.alpha_build_run_id }}"'
  end

  def test_alpha_retry_failure_leaves_the_exact_durable_handoff_unchanged
    workflow = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    failure_step = workflow.split("- name: Document transient Alpha retry failure without replacing the handoff", 2).fetch(1)

    refute_includes failure_step, "sa-release record-failure"
    refute_includes failure_step, "archive-release-to-ghcr.sh push"
    refute_includes failure_step, "GHCR_TOKEN"
    assert_includes failure_step, "exact durable failed-Alpha handoff was left unchanged"
    assert_includes failure_step, 'grep -Fq "Workflow evidence: ${RUN_URL}"'
  end

  def test_alpha_failure_annotation_requires_authorization_and_archive_validation
    workflow = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    authorization = workflow.split("- name: Enforce narrow Alpha-retry authorization", 2).fetch(1)
                            .split("- name: Mint repository-scoped release App token", 2).first
    validation = workflow.split("- name: Pull and validate the preserved beta release state", 2).fetch(1)
                         .split("- name: Reuse or start one Alpha-only Xcode Cloud retry", 2).first
    failure_header = workflow.split("- name: Document transient Alpha retry failure without replacing the handoff", 2).fetch(1)
                             .split("continue-on-error:", 2).first

    assert_includes authorization, "id: authorization"
    assert_includes authorization, 'echo "authorized=true" >> "${GITHUB_OUTPUT}"'
    assert_includes validation, 'file.puts("validated=true")'
    assert_operator validation.index("archive_ref ="), :<, validation.index('file.puts("validated=true")')
    assert_operator validation.index("naming.public_artifacts"), :<, validation.index('file.puts("validated=true")')
    assert_includes failure_header, "steps.authorization.outputs.authorized == 'true'"
    assert_includes failure_header, "steps.release.outputs.validated == 'true'"
  end

  def test_alpha_retry_accepts_a_newer_live_failure_and_binds_it_to_the_durable_predecessor
    workflow = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    validation = workflow.split("- name: Pull and validate the preserved beta release state", 2).fetch(1)
                         .split("- name: Resolve the existing exact Production build without waiting", 2).first
    cloud_start = workflow.index("- name: Reuse or start one Alpha-only Xcode Cloud retry")
    validation_start = workflow.index("- name: Pull and validate the preserved beta release state")

    assert_operator validation_start, :<, cloud_start
    assert_includes validation, 'manifest.fetch("state") == "failed"'
    assert_includes validation, 'failure["component"] == "alpha"'
    assert_includes validation, 'failure["cloud_run_id"].to_s.match?'
    assert_includes validation, 'file.puts("archived_failed_alpha_run_id='
    refute_includes validation, 'failure["cloud_run_id"] == ENV.fetch("FAILED_ALPHA_RUN_ID")'

    archive = workflow.split("- name: Archive the exact Alpha retry handoff", 2).fetch(1)
                      .split("- name: Record asynchronous Alpha retry handoff", 2).first
    assert_includes archive, 'ARCHIVED_FAILED_ALPHA_RUN_ID: ${{ steps.release.outputs.archived_failed_alpha_run_id }}'
    assert_includes archive, 'AUTHORIZED_FAILED_ALPHA_RUN_ID: ${{ inputs.failed_alpha_run_id }}'
    assert_includes archive, 'alpha_retry.fetch("retried_failed_run_id") == authorized'
    assert_includes archive, '"alpha_retry_predecessor" => predecessor'
  end

  def test_api_only_release_jobs_do_not_allocate_macos_runners
    %w[release.yml release_alpha_retry.yml release_finalize.yml].each do |filename|
      workflow = File.read(repo_path(".github/workflows/#{filename}"))
      assert_includes workflow, "runs-on: ubuntu-latest"
      refute_includes workflow, "runs-on: macos-15"
    end

    publisher = File.read(repo_path(".github/workflows/release_publish.yml"))
    assert_equal 1, publisher.scan("runs-on: macos-15").length

    ci = File.read(repo_path(".github/workflows/ci_pr_tests.yml"))
    assert_equal 1, ci.scan("runs-on: macos-26").length
    assert_equal 1, ci.scan("runs-on: macos-15").length
    assert_includes ci, "GitHub-hosted public-repository runner label"

    Dir.glob(repo_path(".github/workflows/*.{yml,yaml}")).each do |path|
      workflow = File.read(path)
      refute_match(/runs-on:\s*(?:\[[^\]]*)?self-hosted/, workflow,
                   "#{File.basename(path)} must not allocate a private self-hosted runner")
    end
  end

  def test_merged_but_untagged_recovery_validates_and_targets_the_exact_release_ancestor
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    context = workflow.index("- name: Resolve naming and the merged-but-untagged recovery path")
    validation = workflow.index("- name: Validate the recovered release target against live main")
    branch_cleanup = workflow.index("- name: Delete a recovered merged release branch")
    release_target = workflow.index("- name: Resolve the exact release target commit")
    prerelease = workflow.index("- name: Create the tag-backed GitHub prerelease")

    assert_operator context, :<, validation
    assert_operator validation, :<, branch_cleanup
    assert_operator branch_cleanup, :<, release_target
    assert_operator release_target, :<, prerelease
    assert_includes workflow[context...validation], "source_release_commit_sha"
    assert_includes workflow[validation...branch_cleanup], "github-validate-release-target"
    assert_includes workflow[release_target...prerelease], 'SOURCE_RELEASE_COMMIT_SHA: ${{ steps.release_context.outputs.source_release_commit_sha }}'
    assert_includes workflow[release_target...prerelease], 'File.read("release-target-validation.json")'
  end

  def test_only_merged_but_untagged_resume_may_start_from_an_ancestor_of_dispatch_main
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    authorization = workflow.split("- name: Enforce release authorization", 2).fetch(1)
                            .split("- name: Mint repository-scoped release App token", 2).first
    context = workflow.split("- name: Resolve naming and the merged-but-untagged recovery path", 2).fetch(1)
                      .split("- name: Validate the recovered release target against live main", 2).first

    assert_includes authorization, '"${RELEASE_MODE}" != "resume"'
    assert_includes authorization, "Prove the frozen release SHA is on dispatch main"
    assert_includes authorization, '/compare/${EXPECTED_SHA}...${DISPATCH_SHA}'
    assert_includes context, "dispatch_main_advanced && !resume_without_pr"
    assert_includes context, 'source_release_commit_sha == ENV.fetch("APPROVED_MAIN_SHA")'
  end

  def test_tag_without_release_resume_is_reconciled_before_skipping_the_pr
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    context = workflow.split("- name: Resolve naming and the merged-but-untagged recovery path", 2).fetch(1)
                      .split("- name: Validate the recovered release target against live main", 2).first
    target = workflow.split("- name: Resolve the exact release target commit", 2).fetch(1)
                     .split("- name: Create the tag-backed GitHub prerelease", 2).first

    assert_equal 2, workflow.scan('--recover-release-channel "${RELEASE_CHANNEL}"').length
    assert_equal 2, workflow.scan('--recover-release-version "${RELEASE_VERSION}"').length
    assert_equal 2, workflow.scan('"${recovery_args[@]}"').length
    assert_includes context, "%w[resume_after_merge resume_after_tag].include?(recovery_reason)"
    assert_includes target, 'ENV.fetch("RECONCILIATION_REASON")'
  end

  private

  def repo_path(relative_path)
    File.expand_path("../..", __dir__) + "/#{relative_path}"
  end
end
