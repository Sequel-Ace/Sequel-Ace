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
    alpha_step = alpha.split("- name: Preserve Alpha retry failure evidence", 2).fetch(1).lines.first(2).join

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
      ".github/workflows/release_finalize.yml" => "Unauthorized event-finalizer rerun initiator."
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

    feasibility = File.read(repo_path(".github/workflows/release_feasibility.yml"))
    feasibility_exclusion = feasibility.index("- name: Exclude transient feasibility evidence from git status")
    feasibility_probe = feasibility.index("- name: Create the verified GitHub App commit and disposable PR")
    assert_operator feasibility_exclusion, :<, feasibility_probe
    assert_includes feasibility[feasibility_exclusion...feasibility_probe], "/feasibility/"
  end

  def test_ambiguous_app_store_submission_is_polled_before_failure_recording
    workflow = File.read(repo_path(".github/workflows/release.yml"))
    failure_step = workflow.split("- name: Preserve an explanatory failed prerelease", 2).fetch(1)
    reconcile = failure_step.index("reconcile-submission")
    record = failure_step.index("record-failure")

    refute_nil reconcile
    refute_nil record
    assert_operator reconcile, :<, record
    assert_includes failure_step[reconcile...record], "--wait-seconds 900"
    assert_includes failure_step[reconcile...record], "--poll-interval 15"
    assert_includes failure_step, "if bundle exec ruby fastlane/bin/sa-release reconcile-submission"
    assert_includes failure_step[reconcile...record], 'if submission_confirmed="$(ruby -rjson'
    assert_includes failure_step[reconcile...record], "Submission reconciliation failed"
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

  def test_finalizer_is_event_driven_with_an_authorized_manual_fallback
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))

    refute_includes workflow, "schedule:"
    refute_includes workflow, "repository_dispatch:"
    assert_includes workflow, "workflow_dispatch:"
    assert_includes workflow, "SA_WEBHOOK_GITHUB_APP_BOT"
    assert_includes workflow, "EVENT_APP_ID: ${{ inputs.app_id }}"
    assert_includes workflow, '"${EVENT_APP_ID}" == "1518036000"'
    assert_includes workflow, '"${EVENT_NEW_VALUE}" == "READY_FOR_DISTRIBUTION"'
    assert_includes workflow, '"${RELEASE_ACTOR}" == "${WEBHOOK_APP_BOT}"'
    assert_includes workflow, "Manual recovery must not provide webhook-only inputs"
    assert_includes workflow, "App Store finalization event is too old"
    assert_includes workflow, "The exact event-triggered release remains pending"
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

    %w[release.yml release_alpha_retry.yml release_feasibility.yml release_finalize.yml].each do |filename|
      workflow = File.read(repo_path(".github/workflows/#{filename}"))

      assert_equal 2, workflow.scan(action).length
      assert_includes workflow, "oras_1.3.3_darwin_arm64.tar.gz"
      assert_includes workflow, arm64_checksum
      assert_includes workflow, "oras_1.3.3_darwin_amd64.tar.gz"
      assert_includes workflow, amd64_checksum
      refute_includes workflow, "brew install oras"
    end
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
    finalizer_job_env = finalizer.split("environment: sequel-ace-release", 2).fetch(1)
                                 .split("steps:", 2).first
    refute_includes finalizer_job_env, "SA_ASC_KEY_ID"
    refute_includes finalizer_job_env, "SA_ASC_PRIVATE_KEY"
    refute_includes finalizer_job_env, "GHCR_TOKEN"
    refute_includes finalizer_job_env, "SA_GITHUB_TOKEN"
    assert_includes finalizer_job_env, 'SA_ASC_REQUIRE_ISSUER: "1"'

    event = finalizer.split("- name: Resolve the exact App Store version event", 2).fetch(1)
                     .split("- name: Finalize only exact App Store-live releases", 2).first
    assert_includes event, 'SA_ASC_KEY_ID: ${{ secrets.SA_ASC_KEY_ID }}'
    assert_includes event, 'SA_ASC_PRIVATE_KEY: ${{ secrets.SA_ASC_PRIVATE_KEY }}'

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

  def test_finalizer_resolves_and_matches_the_exact_event_version_and_build
    workflow = File.read(repo_path(".github/workflows/release_finalize.yml"))
    resolution = workflow.index("sa-release resolve-app-store-version")
    exact_tag = workflow.index('release_tag="production/${SA_FINALIZE_EVENT_VERSION}-${SA_FINALIZE_EVENT_BUILD}"')
    version_identity = workflow.index('"${manifest_version_id}" == "${SA_FINALIZE_EVENT_VERSION_ID}"')
    build_identity = workflow.index('"${manifest_build_id}" == "${SA_FINALIZE_EVENT_BUILD_ID}"')
    validation = workflow.index("--validate-only")

    assert resolution
    assert exact_tag
    assert version_identity
    assert build_identity
    assert validation
    assert_operator resolution, :<, exact_tag
    assert_operator exact_tag, :<, version_identity
    assert_operator version_identity, :<, build_identity
    assert_operator build_identity, :<, validation
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
    archive = workflow.index('Scripts/archive-release-to-ghcr.sh push "${archive_ref}"')
    public_transition = workflow.index('--output "${work_directory}/finalization.json"')

    assert validation
    assert archive
    assert public_transition
    assert_operator validation, :<, archive
    assert_operator archive, :<, public_transition
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

  def test_alpha_failure_uses_the_checkpoint_preserving_recorder
    workflow = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    failure_step = workflow.split("- name: Preserve Alpha retry failure evidence", 2).fetch(1)

    assert_includes failure_step, "sa-release record-failure"
    refute_includes failure_step, "--state failed"
  end

  def test_alpha_failure_cannot_mutate_until_authorization_and_archive_validation_succeed
    workflow = File.read(repo_path(".github/workflows/release_alpha_retry.yml"))
    authorization = workflow.split("- name: Enforce narrow Alpha-retry authorization", 2).fetch(1)
                            .split("- name: Mint repository-scoped release App token", 2).first
    validation = workflow.split("- name: Pull and validate the preserved beta release state", 2).fetch(1)
                         .split("- name: Reuse or start one Alpha-only Xcode Cloud retry", 2).first
    failure_header = workflow.split("- name: Preserve Alpha retry failure evidence", 2).fetch(1).lines.first(2).join

    assert_includes authorization, "id: authorization"
    assert_includes authorization, 'echo "authorized=true" >> "${GITHUB_OUTPUT}"'
    assert_includes validation, 'file.puts("validated=true")'
    assert_operator validation.index("archive_ref ="), :<, validation.index('file.puts("validated=true")')
    assert_operator validation.index("naming.public_artifacts"), :<, validation.index('file.puts("validated=true")')
    assert_includes failure_header, "steps.authorization.outputs.authorized == 'true'"
    assert_includes failure_header, "steps.release.outputs.validated == 'true'"
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

  private

  def repo_path(relative_path)
    File.expand_path("../..", __dir__) + "/#{relative_path}"
  end
end
