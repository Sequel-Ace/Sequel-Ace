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
    prerelease_step = release.split("- name: Preserve an explanatory failed prerelease", 2).fetch(1).lines.first(2).join
    alpha = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    alpha_step = alpha.split("- name: Document transient Alpha retry failure without replacing the handoff", 2).fetch(1).lines.first(2).join

    assert_includes cleanup_token, "failure() || cancelled()"
    assert_includes cleanup_step, "failure() || cancelled()"
    assert_includes prerelease_step, "failure() || cancelled()"
    assert_includes alpha_step, "failure() || cancelled()"
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
    assert_includes publisher, 'cron: "11,41 * * * *"'
    assert_includes publisher, "workflow_run:"
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
    assert_includes gate, '.author.login == "sequel-ace-release-automation[bot]"'
    assert_includes gate, "has unreadable private handoff state; refusing to overlap it"
    refute_includes gate, "if Scripts/archive-release-to-ghcr.sh pull"
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

  def test_publisher_skips_unreadable_scheduled_candidates_but_fails_an_explicit_recovery
    workflow = File.read(repo_path(".github/workflows/release_publish.yml"))
    discovery = workflow.split("- name: Inspect exact Cloud runs once", 2).fetch(1)
                        .split("  cloud_failure:", 2).first

    assert_includes discovery, 'if [[ -n "${REQUESTED_TAG}" ]]'
    assert_includes discovery, "Requested release \${release_tag} has no readable private handoff archive."
    assert_includes discovery, "it was skipped."
    assert_includes discovery, "unreadable=$((unreadable + 1))"
    assert_includes discovery, "candidate archive(s) were unreadable and require investigation."
    skipped = discovery.index("it was skipped.")
    assert_operator skipped, :<, discovery.index("continue", skipped)
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
    assert_includes transient, "left unchanged so the next short check can retry safely"
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
    assert_includes discovery, 'select(.author.login == "sequel-ace-release-automation[bot]")'
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
    assert_includes discovery, "gh release list"
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
    checkout = workflow.index("- name: Check out the frozen main commit")
    proof = workflow[ancestry...app_token]

    assert_operator authorization, :<, ancestry
    assert_operator ancestry, :<, app_token
    assert_operator app_token, :<, checkout
    assert_includes workflow[authorization...ancestry], '[[ "${EXPECTED_SHA}" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]'
    assert_includes proof, '/compare/${EXPECTED_SHA}...${DISPATCH_SHA}'
    assert_includes proof, '"${comparison_status}" == "identical" || "${comparison_status}" == "ahead"'
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
    assert_equal 5, publisher.scan(action).length
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
    assert_equal 4, workflow.scan('ref: ${{ github.sha }}').length
    refute_includes workflow, "ref: main"
    assert_includes workflow, 'SOURCE_HEAD_BRANCH: ${{ github.event.workflow_run.head_branch }}'
    assert_includes workflow, '[[ "${SOURCE_HEAD_BRANCH}" == "main" ]]'
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
                      .split("- name: Finalize only exact App Store-live releases", 2).first
    assert_includes access, 'SA_ASC_KEY_ID: ${{ secrets.SA_ASC_KEY_ID }}'
    assert_includes access, 'SA_ASC_PRIVATE_KEY: ${{ secrets.SA_ASC_PRIVATE_KEY }}'

    finalize = finalizer.split("- name: Finalize only exact App Store-live releases", 2).fetch(1)
    assert_includes finalize, 'GHCR_TOKEN: ${{ github.token }}'
    assert_includes finalize, 'SA_GITHUB_TOKEN: ${{ github.token }}'
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

    [discovery, execution].each do |step|
      listing = step.index("gh release list")
      prerelease_filter = step.index(".isPrerelease == true")
      production_filter = step.index('startsWith("production/")') || step.index('startswith("production/")')

      assert listing
      assert prerelease_filter
      assert production_filter
      assert_operator listing, :<, prerelease_filter
      assert_operator prerelease_filter, :<, production_filter
    end
    assert_operator execution.index('startswith("production/")'), :<, execution.index("--validate-only")
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
    failure_header = workflow.split("- name: Document transient Alpha retry failure without replacing the handoff", 2).fetch(1).lines.first(2).join

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
