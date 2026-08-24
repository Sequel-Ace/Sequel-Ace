# frozen_string_literal: true

require "base64"
require "date"
require "digest"
require "fileutils"
require "optparse"

module SequelAceRelease
  class CLI
    SUBMISSION_SCHEDULE_SAFETY_SECONDS = 15 * 60
    SUBMITTED_APP_STORE_STATES = SubmissionReconciler::SUBMITTED_STATES
    FAILED_APP_STORE_STATES = %w[
      DEVELOPER_REJECTED INVALID_BINARY METADATA_REJECTED REJECTED
    ].freeze

    def self.run(argv, out: $stdout, err: $stderr, env: ENV, clock: -> { Time.now.utc })
      new(out: out, err: err, env: env, clock: clock).run(argv)
    end

    def initialize(out:, err:, env:, clock: -> { Time.now.utc })
      @out = out
      @err = err
      @env = env
      @clock = clock
      @runner = CommandRunner.new
    end

    def run(argv)
      command = argv.shift
      case command
      when "plan" then plan(argv)
      when "guard" then guard(argv)
      when "prepare" then prepare(argv)
      when "reconcile-build" then reconcile_build(argv)
      when "verify-artifact" then verify_artifact(argv)
      when "verify-artifact-set" then verify_artifact_set(argv)
      when "submit" then submit(argv)
      when "finalize" then finalize(argv)
      when "github-prepare-pr" then github_prepare_pr(argv)
      when "github-cleanup-branch" then github_cleanup_branch(argv)
      when "github-wait-checks" then github_wait_checks(argv)
      when "github-merge-pr" then github_merge_pr(argv)
      when "github-validate-release-target" then github_validate_release_target(argv)
      when "github-verify-release-tag" then github_verify_release_tag(argv)
      when "github-release-publisher-mode" then github_release_publisher_mode(argv)
      when "github-create-release" then github_create_release(argv)
      when "github-public-assets-status" then github_public_assets_status(argv)
      when "github-upload-asset" then github_upload_asset(argv)
      when "validate-publish-handoff" then validate_publish_handoff(argv)
      when "validate-forward-recovery" then validate_forward_recovery(argv)
      when "cloud-status" then cloud_status(argv)
      when "wait-cloud" then wait_cloud(argv)
      when "download-cloud-artifacts" then download_cloud_artifacts(argv)
      when "retry-alpha" then retry_alpha(argv)
      when "create-manifest" then create_manifest(argv)
      when "update-manifest" then update_manifest(argv)
      when "reconcile-submission" then reconcile_submission(argv)
      when "record-failure" then record_failure(argv)
      when "version" then emit("version" => SequelAceRelease::VERSION)
      when nil, "help", "--help", "-h"
        @out.puts(help)
      else
        raise ValidationError, "unknown command: #{command}"
      end
      0
    rescue Error, OptionParser::ParseError, KeyError, JSON::ParserError => e
      @err.puts("release tool stopped: #{e.message}")
      1
    end

    private

    def guard(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release guard --actor LOGIN --triggering-actor LOGIN --mode MODE --ref REF --current-sha SHA --expected-sha SHA --channel CHANNEL --version VERSION --confirmation TEXT --enabled VALUE"
        value.on("--actor LOGIN") { |item| options[:actor] = item }
        value.on("--triggering-actor LOGIN") { |item| options[:triggering_actor] = item }
        value.on("--mode MODE") { |item| options[:mode] = item }
        value.on("--ref REF") { |item| options[:ref] = item }
        value.on("--current-sha SHA") { |item| options[:current_sha] = item }
        value.on("--expected-sha SHA") { |item| options[:expected_sha] = item }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--recovery-tag TAG") { |item| options[:recovery_tag] = item }
        value.on("--confirmation TEXT") { |item| options[:confirmation] = item }
        value.on("--enabled VALUE") { |item| options[:enabled] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :actor, :triggering_actor, :mode, :ref, :current_sha, :expected_sha, :channel, :version, :confirmation, :enabled)
      output = options.delete(:output)
      emit(DeploymentGuard.new.validate!(**options), output)
    end

    def plan(arguments)
      options = { channel: "production", main_ref: "HEAD" }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release plan [options]"
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--target-version VERSION") { |item| options[:target_version] = item }
        value.on("--base-tag TAG") { |item| options[:base_tag] = item }
        value.on("--main-ref REF") { |item| options[:main_ref] = item }
        value.on("--app-store-notes FILE") { |item| options[:app_store_notes] = File.read(item) }
        value.on("--expected-approval-sha SHA") { |item| options[:expected_approval_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      github = github_client(optional: true)
      result = Planner.new(github: github).plan(**options.slice(
        :channel, :target_version, :base_tag, :main_ref, :app_store_notes
      ))
      if options[:expected_approval_sha]
        Approval.from_hash(result.fetch("approval")).verify!(options[:expected_approval_sha])
      end
      emit(result, options[:output])
    end

    def prepare(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release prepare --version VERSION --build BUILD --base-tag TAG --changelog-base-tag TAG [options]"
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--base-tag TAG") { |item| options[:base_tag] = item }
        value.on("--expected-base-sha SHA") { |item| options[:expected_base_sha] = item }
        value.on("--changelog-base-tag TAG") { |item| options[:changelog_base_tag] = item }
        value.on("--expected-changelog-base-sha SHA") { |item| options[:expected_changelog_base_sha] = item }
        value.on("--expected-main-sha SHA") { |item| options[:expected_main_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(
        options,
        :version, :build, :channel, :base_tag, :expected_base_sha,
        :changelog_base_tag, :expected_changelog_base_sha
      )
      Config.validate_channel!(options[:channel])

      git = GitRepository.new
      git.ensure_clean!
      current_sha = git.sha
      if options[:expected_main_sha] && current_sha != options[:expected_main_sha]
        raise ValidationError, "HEAD #{current_sha} does not match frozen main #{options[:expected_main_sha]}"
      end
      resolved_base_sha = git.sha(options[:base_tag])
      unless resolved_base_sha == options[:expected_base_sha]
        raise ValidationError, "comparison tag does not match its approved SHA"
      end
      resolved_changelog_base_sha = git.sha(options[:changelog_base_tag])
      unless resolved_changelog_base_sha == options[:expected_changelog_base_sha]
        raise ValidationError, "changelog base tag does not match its approved SHA"
      end

      version_result = VersionFiles.new.update!(
        version: options[:version],
        build: options[:build],
        channel: options[:channel]
      )
      @runner.run(
        Config.repo_root.join("Scripts/generate-changelog.sh"),
        options[:version],
        env: { "RANGE_START" => options[:changelog_base_tag], "RANGE_END" => current_sha }
      )
      changed_paths = git.changed_paths
      validate_preparation_paths!(changed_paths)
      emit({
        "channel" => options[:channel],
        "head_sha" => current_sha,
        "base_tag" => options[:base_tag],
        "base_sha" => resolved_base_sha,
        "changelog_base_tag" => options[:changelog_base_tag],
        "changelog_base_sha" => resolved_changelog_base_sha,
        "versions" => version_result,
        "changed_paths" => changed_paths
      }, options[:output])
    end

    def reconcile_build(arguments)
      options = { cloud_runs: [] }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release reconcile-build [options]"
        value.on("--source-build BUILD", Integer) { |item| options[:source_build] = item }
        value.on("--highest-tag-build BUILD", Integer) { |item| options[:highest_tag_build] = item }
        value.on("--highest-asc-build BUILD", Integer) { |item| options[:highest_asc_build] = item }
        value.on("--expected-target-build BUILD", Integer) { |item| options[:expected_target_build] = item }
        value.on("--cloud-runs FILE") { |item| options[:cloud_runs] = read_json(item) }
        value.on("--workflow-id ID") { |item| options[:workflow_id] = item }
        value.on("--source-tagged") { options[:source_tagged] = true }
        value.on("--recover-release-channel CHANNEL") { |item| options[:recover_release_channel] = item }
        value.on("--recover-release-version VERSION") { |item| options[:recover_release_version] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      git = GitRepository.new
      source_build = options[:source_build] || VersionFiles.new.current.fetch("build")
      canonical_tags = git.tags("production/*") + git.tags("beta/*")
      highest_tag = options[:highest_tag_build] || highest_build_from_tags(canonical_tags)
      asc_client = nil
      if options[:workflow_id] || !options.key?(:highest_asc_build)
        asc_client = app_store_client
      end
      runs = options[:workflow_id] ? asc_client.workflow_runs(options[:workflow_id]) : Array(options[:cloud_runs])
      highest_asc = options.fetch(:highest_asc_build) { asc_client.highest_app_build(Config::PRODUCTION_APP_ID) }
      source_tags = git.tags("production/*-#{source_build}") + git.tags("beta/*-#{source_build}")
      source_tagged = options.fetch(:source_tagged, false) || source_tags.any?
      source_release_commit_sha = git.latest_commit_changing_all(release_paths)
      recovery_tag = recover_release_tag(
        options: options,
        git: git,
        source_build: source_build,
        source_release_commit_sha: source_release_commit_sha,
        runs: runs,
        app_store_client: asc_client
      )

      result = BuildReconciler.new.reconcile(
        source_build: source_build,
        highest_tag_build: highest_tag,
        highest_asc_build: highest_asc,
        cloud_runs: runs,
        source_tagged: source_tagged,
        source_release_commit_sha: source_release_commit_sha,
        expected_target_build: options[:expected_target_build],
        recover_release_tag: recovery_tag,
        production_workflow_id: options[:workflow_id]
      )
      emit(result.to_h.merge("production_cloud_runs" => runs), options[:output])
    end

    def verify_artifact(arguments)
      options = { launch: false, any_build: false }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release verify-artifact --artifact PATH --version VERSION --build BUILD --channel CHANNEL"
        value.on("--artifact PATH") { |item| options[:path] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--any-build") { options[:any_build] = true }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--release-tag TAG") { |item| options[:release_tag] = item }
        value.on("--launch") { options[:launch] = true }
        value.on("--output-zip FILE") { |item| options[:output_zip] = item }
        value.on("--sha256 SHA") { |item| options[:expected_sha256] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :path, :version, :channel)
      raise OptionParser::MissingArgument, "build" if options[:build].nil? && !options[:any_build]
      output = options.delete(:output)
      emit(ArtifactVerifier.new.verify(**options), output)
    end

    def github_prepare_pr(arguments)
      options = { iteration: 1 }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-prepare-pr --approval FILE --approval-sha SHA --build BUILD --release-body FILE"
        value.on("--approval FILE") { |item| options[:approval_file] = item }
        value.on("--approval-sha SHA") { |item| options[:approval_sha] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--iteration NUMBER", Integer) { |item| options[:iteration] = item }
        value.on("--release-body FILE") { |item| options[:release_body] = File.read(item) }
        value.on("--base-sha SHA") { |item| options[:base_sha] = item }
        value.on("--recovery-evidence FILE") { |item| options[:recovery_evidence] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :approval_file, :approval_sha, :build, :release_body)

      approval = approval_from_file(options[:approval_file])
      approval.verify!(options[:approval_sha])
      git = GitRepository.new
      approved_sha = approval.payload.fetch("main_sha")
      expected_sha = options[:base_sha] || approved_sha
      if expected_sha != approved_sha
        raise ValidationError, "advanced release PR base requires validated forward-recovery evidence" unless options[:recovery_evidence]

        recovery = read_json(options[:recovery_evidence])
        validate_forward_recovery_pr_evidence!(
          recovery,
          approval: approval,
          approval_sha: options[:approval_sha],
          expected_sha: expected_sha,
          requested_build: options[:build]
        )
      end
      raise ValidationError, "release PR is not based on the frozen main SHA" unless git.sha == expected_sha

      naming = ReleaseNaming.new(
        channel: approval.payload.fetch("channel"),
        version: approval.payload.fetch("target_version"),
        build: options[:build],
        iteration: options[:iteration]
      )
      paths = git.changed_paths
      validate_preparation_paths!(paths)
      commit = github_client.create_bot_commit(
        base_sha: expected_sha,
        branch: naming.branch,
        message: "Prepare #{naming.version} (#{naming.build}) release #changed",
        repository_root: Config.repo_root,
        changed_paths: paths
      )
      recovery = { "naming" => naming.to_h, "commit" => commit, "pull_request" => nil }
      File.write(options[:output], CanonicalJSON.pretty(recovery)) if options[:output]
      pull = github_client.create_pull_request(
        branch: naming.branch,
        title: "#changed Prepare #{naming.version} (#{naming.build}) release",
        body: release_pull_request_body(naming, options[:release_body])
      )
      emit({ "naming" => naming.to_h, "commit" => commit, "pull_request" => pull }, options[:output])
    end

    def github_cleanup_branch(arguments)
      options = { reconcile_prepared_tree: false }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-cleanup-branch --branch BRANCH --expected-sha SHA [--base-sha SHA --reconcile-prepared-tree]"
        value.on("--branch BRANCH") { |item| options[:branch] = item }
        value.on("--expected-sha SHA") { |item| options[:expected_sha] = item }
        value.on("--base-sha SHA") { |item| options[:base_sha] = item }
        value.on("--reconcile-prepared-tree") { options[:reconcile_prepared_tree] = true }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :branch, :expected_sha)
      if options[:reconcile_prepared_tree] && options[:base_sha].to_s.empty?
        raise OptionParser::MissingArgument, "base-sha"
      end
      git = GitRepository.new if options[:reconcile_prepared_tree]
      result = github_client.cleanup_release_branch(
        branch: options[:branch],
        expected_sha: options[:expected_sha],
        base_sha: options[:base_sha],
        repository_root: options[:reconcile_prepared_tree] ? Config.repo_root : nil,
        changed_paths: git&.changed_paths
      )
      emit(result, options[:output])
    end

    def verify_artifact_set(arguments)
      options = { launch: false, any_build: false }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release verify-artifact-set --index FILE --version VERSION --channel CHANNEL --output-zip FILE"
        value.on("--index FILE") { |item| options[:index] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--any-build") { options[:any_build] = true }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--release-tag TAG") { |item| options[:release_tag] = item }
        value.on("--launch") { options[:launch] = true }
        value.on("--output-zip FILE") { |item| options[:output_zip] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :index, :version, :channel, :output_zip)
      raise OptionParser::MissingArgument, "build" if options[:build].nil? && !options[:any_build]

      artifacts = read_json(options[:index]).fetch("artifacts")
      failures = []
      verifier = ArtifactVerifier.new
      artifacts.each do |artifact|
        begin
          result = verifier.verify(
            path: artifact.fetch("path"),
            version: options[:version],
            build: options[:build],
            channel: options[:channel],
            launch: options[:launch],
            output_zip: options[:output_zip],
            any_build: options[:any_build],
            expected_sha256: artifact["sha256"],
            release_tag: options[:release_tag]
          )
          return emit(result.merge("cloud_artifact" => artifact), options[:output])
        rescue ValidationError, CommandError => e
          failures << "#{artifact['file_name']}: #{e.message.lines.first.to_s.strip}"
        end
      end

      raise ValidationError, "no Cloud artifact passed verification (#{failures.join('; ')})"
    end

    def github_wait_checks(arguments)
      options = { timeout: 7_200 }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-wait-checks --head-sha SHA --required-check NAME"
        value.on("--head-sha SHA") { |item| options[:head_sha] = item }
        value.on("--required-check NAME") { |item| (options[:required_checks] ||= []) << item }
        value.on("--require-all-checks") { options[:require_all_checks] = true }
        value.on("--timeout SECONDS", Integer) { |item| options[:timeout] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :head_sha, :required_checks)

      runs = github_client.wait_for_checks(
        commit_sha: options[:head_sha],
        required_names: options[:required_checks],
        timeout_seconds: options[:timeout],
        require_all: options[:require_all_checks] == true
      )
      emit({
        "head_sha" => options[:head_sha],
        "checks" => runs.map { |run| run.slice("id", "name", "status", "conclusion", "started_at", "completed_at") }
      }, options[:output])
    end

    def github_merge_pr(arguments)
      options = { timeout: 7_200 }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-merge-pr --pr NUMBER --head-sha SHA --expected-base-sha SHA --required-check NAME"
        value.on("--pr NUMBER", Integer) { |item| options[:pr] = item }
        value.on("--head-sha SHA") { |item| options[:head_sha] = item }
        value.on("--expected-base-sha SHA") { |item| options[:expected_base_sha] = item }
        value.on("--required-check NAME") { |item| (options[:required_checks] ||= []) << item }
        value.on("--require-all-checks") { options[:require_all_checks] = true }
        value.on("--timeout SECONDS", Integer) { |item| options[:timeout] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :pr, :head_sha, :expected_base_sha, :required_checks)

      client = github_client
      pull = client.pull_request(options[:pr])
      raise ValidationError, "release PR head changed after creation" unless pull.dig("head", "sha") == options[:head_sha]
      raise ValidationError, "main changed after release approval" unless pull.dig("base", "sha") == options[:expected_base_sha]
      client.wait_for_checks(
        commit_sha: options[:head_sha],
        required_names: options[:required_checks],
        timeout_seconds: options[:timeout],
        require_all: options[:require_all_checks] == true
      )
      pull = client.pull_request(options[:pr])
      raise ValidationError, "release PR head changed while checks ran" unless pull.dig("head", "sha") == options[:head_sha]
      raise ValidationError, "main changed while release checks ran" unless pull.dig("base", "sha") == options[:expected_base_sha]
      merge = client.merge_pull_request(number: options[:pr], expected_head_sha: options[:head_sha])
      client.delete_branch(pull.dig("head", "ref"))
      emit(merge, options[:output])
    end

    def github_create_release(arguments)
      options = { iteration: 1 }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-create-release --channel CHANNEL --version VERSION --build BUILD --target-sha SHA --body FILE [--publisher user|app]"
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--iteration NUMBER", Integer) { |item| options[:iteration] = item }
        value.on("--target-sha SHA") { |item| options[:target_sha] = item }
        value.on("--body FILE") { |item| options[:body] = File.read(item) }
        value.on("--publisher MODE") { |item| options[:publisher] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :channel, :version, :build, :target_sha, :body)
      naming = ReleaseNaming.new(**options.slice(:channel, :version, :build, :iteration))
      client = github_client
      target_validation = client.validate_release_target!(
        target_sha: options[:target_sha],
        protected_paths: release_paths
      )
      existing = client.release_by_tag_if_exists(naming.tag)
      if existing
        expected_publisher = ReleasePublisher.validate!(
          tag: naming.tag,
          login: existing.dig("author", "login"),
          id: existing.dig("author", "id")
        )
        expected_author_id = existing.dig("author", "id")
        publisher_validation = {
          "login" => expected_publisher,
          "id" => expected_author_id,
          "mode" => "existing",
          "repository" => Config::REPOSITORY
        }.compact
        tag = client.validate_release_tag(
          tag: naming.tag,
          target_sha: options[:target_sha]
        )
        release = client.validate_existing_release(
          release: existing,
          tag: naming.tag,
          target_sha: options[:target_sha],
          title: naming.title,
          body: options[:body],
          expected_author_login: expected_publisher,
          expected_author_id: expected_author_id
        )
      else
        if options[:publisher].nil?
          raise ValidationError, "new GitHub releases require an explicit user or app publisher mode"
        end
        publication_mode = options[:publisher].to_sym
        unless %i[user app].include?(publication_mode)
          raise ValidationError, "GitHub release publisher mode must be user or app"
        end
        if publication_mode == :user
          publisher = github_user_publisher_client
          expected_publisher = ReleasePublisher::USER_LOGIN
          expected_author_id = ReleasePublisher::USER_ID
          publisher_validation = publisher.validate_release_publisher!(
            expected_login: expected_publisher,
            expected_id: expected_author_id
          )
        else
          publisher = client
          publisher_validation = publisher.validate_release_app_publisher!(
            expected_app_id: ReleasePublisher::RELEASE_APP_ID,
            expected_client_id: @env["SA_RELEASE_GITHUB_APP_CLIENT_ID"],
            expected_app_slug: @env["SA_RELEASE_GITHUB_APP_SLUG"],
            expected_installation_id: @env["SA_RELEASE_GITHUB_APP_INSTALLATION_ID"]
          )
          expected_publisher = publisher_validation.fetch("login")
          expected_author_id = ReleasePublisher::RELEASE_APP_BOT_ID
        end
        tag = client.create_or_validate_release_tag(
          tag: naming.tag,
          target_sha: options[:target_sha]
        )
        release = publisher.create_or_validate_release(
          tag: naming.tag,
          target_sha: options[:target_sha],
          title: naming.title,
          body: options[:body],
          expected_author_login: expected_publisher,
          expected_author_id: expected_author_id
        )
      end
      ReleasePublisher.validate!(
        tag: naming.tag,
        login: release.dig("author", "login"),
        id: release.dig("author", "id")
      )
      emit({
        "naming" => naming.to_h,
        "target_validation" => target_validation,
        "publisher_validation" => publisher_validation,
        "tag" => tag,
        "release" => release
      }, options[:output])
    end

    def github_release_publisher_mode(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-release-publisher-mode --tag TAG"
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :tag)
      ReleasePublisher.validate_tag!(options[:tag])

      existing = github_client.release_by_tag_if_exists(options[:tag])
      reason = nil
      publisher_validation = nil
      mode = if existing
               ReleasePublisher.validate!(
                 tag: options[:tag],
                 login: existing.dig("author", "login"),
                 id: existing.dig("author", "id")
               )
               reason = "existing_release"
               :existing
             elsif @env["SA_RELEASE_GITHUB_PUBLISHER_TOKEN"].to_s.empty?
               reason = "user_credential_absent"
               :app
             else
               begin
                 publisher_validation = github_user_publisher_client.validate_release_publisher!(
                   expected_login: ReleasePublisher::USER_LOGIN,
                   expected_id: ReleasePublisher::USER_ID
                 )
                 reason = "user_credential_available"
                 :user
               rescue APIError => error
                 raise unless error.status == 401

                 reason = "user_credential_expired_or_revoked"
                 :app
               end
             end
      emit({
        "mode" => mode.to_s,
        "reason" => reason,
        "publisher_validation" => publisher_validation,
        "existing_release_id" => existing && existing["id"]
      }, options[:output])
    end

    def github_validate_release_target(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-validate-release-target --target-sha SHA"
        value.on("--target-sha SHA") { |item| options[:target_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :target_sha)
      result = github_client.validate_release_target!(
        target_sha: options[:target_sha],
        protected_paths: release_paths
      )
      emit(result, options[:output])
    end

    def github_verify_release_tag(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-verify-release-tag --tag TAG --target-sha SHA"
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--target-sha SHA") { |item| options[:target_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :tag, :target_sha)
      result = github_client.validate_release_tag(
        tag: options[:tag],
        target_sha: options[:target_sha]
      )
      emit(result, options[:output])
    end

    def github_upload_asset(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-upload-asset --tag TAG --file FILE --manifest FILE --notes FILE [--name NAME] [--integrity-failure-marker FILE]"
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--file FILE") { |item| options[:file] = item }
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--notes FILE") { |item| options[:notes] = item }
        value.on("--name NAME") { |item| options[:name] = item }
        value.on("--integrity-failure-marker FILE") { |item| options[:integrity_failure_marker] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :tag, :file, :manifest, :notes)
      begin
        client = github_client
        manifest = Manifest.read(options[:manifest])
        handoff = PublishHandoff.new(github: client).validate(
          manifest: manifest,
          tag: options[:tag],
          app_store_notes: File.read(options[:notes])
        )
        raise ValidationError, "release handoff is not eligible for artifact upload" unless handoff.fetch("eligible")

        release = client.release_by_tag(options[:tag])
        unless release["id"] == handoff.fetch("github_release_id")
          raise ValidationError, "release identity changed before artifact upload"
        end
        payload = GitHubReleasePayload.new(
          release: release,
          expected_digests: release_asset_sha256s!(manifest.to_h)
        ).validate
        if payload.fetch("mode") == "manual_web_upload"
          raise ValidationError,
                "GitHub API asset uploads cannot preserve the release's #{payload.fetch('compatibility_profile')} " \
                "payload; upload through a compatible GitHub user session and run github-public-assets-status"
        end
        asset_name = options[:name] || File.basename(options[:file])
        expected_sha256 = verified_release_asset_sha256!(
          manifest: manifest,
          path: options[:file],
          name: asset_name
        )
        response = client.upload_release_asset(
          release: release,
          path: options[:file],
          name: asset_name,
          expected_sha256: expected_sha256
        )
      rescue IntegrityError
        write_integrity_failure_marker(options[:integrity_failure_marker])
        raise
      end
      emit(response, options[:output])
    end

    def github_public_assets_status(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-public-assets-status --tag TAG --manifest FILE --notes FILE [--integrity-failure-marker FILE]"
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--notes FILE") { |item| options[:notes] = item }
        value.on("--integrity-failure-marker FILE") { |item| options[:integrity_failure_marker] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :tag, :manifest, :notes)

      client = github_client
      manifest = Manifest.read(options[:manifest])
      handoff = PublishHandoff.new(github: client).validate(
        manifest: manifest,
        tag: options[:tag],
        app_store_notes: File.read(options[:notes])
      )
      raise ValidationError, "release handoff is not eligible for public asset validation" unless handoff.fetch("eligible")

      release = client.release_by_tag(options[:tag])
      unless release["id"] == handoff.fetch("github_release_id")
        raise ValidationError, "release identity changed before public asset validation"
      end
      validator = GitHubReleasePayload.new(
        release: release,
        expected_digests: release_asset_sha256s!(manifest.to_h)
      )
      result = validator.validate
      if result.fetch("ready")
        result["release_feed_entries_verified"] = validator.validate_public_feed!(client.public_release_feed_page)
      end
      emit(result.merge(
        "tag" => options[:tag],
        "github_release_id" => release.fetch("id")
      ), options[:output])
    rescue IntegrityError
      write_integrity_failure_marker(options[:integrity_failure_marker])
      raise
    end

    def cloud_status(arguments)
      options = { allow_any_build: false }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release cloud-status --workflow-id ID --app-id ID --version VERSION --tag TAG --build BUILD --commit SHA"
        value.on("--workflow-id ID") { |item| options[:workflow_id] = item }
        value.on("--app-id ID") { |item| options[:app_id] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--allow-any-build") { options[:allow_any_build] = true }
        value.on("--run-id ID") { |item| options[:run_id] = item }
        value.on("--commit SHA") { |item| options[:commit] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :workflow_id, :app_id, :version, :tag, :commit)
      raise OptionParser::MissingArgument, "build" if options[:build].nil? && !options[:allow_any_build]
      Version.validate!(options[:version])

      result = CloudRunStatus.new(client: app_store_client).readiness(**options.slice(
        :workflow_id, :app_id, :version, :tag, :build, :run_id, :commit
      ))
      emit(result, options[:output])
    end

    def validate_publish_handoff(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release validate-publish-handoff --manifest FILE --tag TAG --notes FILE [--integrity-failure-marker FILE]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--notes FILE") { |item| options[:notes] = item }
        value.on("--integrity-failure-marker FILE") { |item| options[:integrity_failure_marker] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest, :tag, :notes)

      result = PublishHandoff.new(github: github_client).validate(
        manifest: Manifest.read(options[:manifest]),
        tag: options[:tag],
        app_store_notes: File.read(options[:notes])
      )
      emit(result, options[:output])
    rescue IntegrityError
      write_integrity_failure_marker(options[:integrity_failure_marker])
      raise
    end

    def validate_forward_recovery(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release validate-forward-recovery --manifest FILE --approval FILE --approval-sha SHA --release-body FILE --tag TAG --current-sha SHA --channel CHANNEL --version VERSION --previous-tag TAG"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--approval FILE") { |item| options[:approval] = item }
        value.on("--approval-sha SHA") { |item| options[:approval_sha] = item }
        value.on("--release-body FILE") { |item| options[:release_body] = item }
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--current-sha SHA") { |item| options[:current_sha] = item }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--previous-tag TAG") { |item| options[:previous_tag] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(
        options,
        :manifest, :approval, :approval_sha, :release_body, :tag,
        :current_sha, :channel, :version, :previous_tag
      )

      result = ForwardBuildRecovery.new(github: github_client).validate(
        manifest: Manifest.read(options[:manifest]),
        approval: approval_from_file(options[:approval]),
        approval_sha: options[:approval_sha],
        release_body: File.binread(options[:release_body]),
        tag: options[:tag],
        current_sha: options[:current_sha],
        channel: options[:channel],
        version: options[:version],
        previous_tag: options[:previous_tag]
      )
      emit(result, options[:output])
    end

    def wait_cloud(arguments)
      options = { timeout: 10_800, interval: 30, allow_any_build: false }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release wait-cloud --workflow-id ID --app-id ID --version VERSION --tag TAG --build BUILD --commit SHA"
        value.on("--workflow-id ID") { |item| options[:workflow_id] = item }
        value.on("--app-id ID") { |item| options[:app_id] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--allow-any-build") { options[:allow_any_build] = true }
        value.on("--run-id ID") { |item| options[:run_id] = item }
        value.on("--commit SHA") { |item| options[:commit] = item }
        value.on("--timeout SECONDS", Integer) { |item| options[:timeout] = item }
        value.on("--interval SECONDS", Integer) { |item| options[:interval] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :workflow_id, :app_id, :version, :tag, :commit)
      raise OptionParser::MissingArgument, "build" if options[:build].nil? && !options[:allow_any_build]
      Version.validate!(options[:version])

      inspector = CloudRunStatus.new(client: app_store_client)
      deadline = Time.now + options[:timeout]
      loop do
        result = inspector.readiness(**options.slice(
          :workflow_id, :app_id, :version, :tag, :build, :run_id, :commit
        ))
        if result.fetch("readiness") == "ready"
          return emit(result.except("readiness", "reason"), options[:output])
        end
        if result.fetch("readiness") == "failed"
          label = options[:build] || result["number"] || "for commit #{options[:commit]}"
          raise ValidationError, "Xcode Cloud build #{label} completed with #{result['completion_status']}"
        end
        label = options[:build] || "for commit #{options[:commit]}"
        raise ValidationError, "timed out waiting for Xcode Cloud build #{label}" if Time.now >= deadline

        sleep(options[:interval])
      end
    end

    def download_cloud_artifacts(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release download-cloud-artifacts --run-id ID --output-directory DIR"
        value.on("--run-id ID") { |item| options[:run_id] = item }
        value.on("--output-directory DIR") { |item| options[:directory] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :run_id, :directory)

      client = app_store_client
      artifacts = client.run_artifacts(options[:run_id])
      downloadable = artifacts.select { |artifact| artifact.dig("attributes", "downloadUrl").to_s.start_with?("https://") }
      raise ValidationError, "Xcode Cloud build exposes no downloadable artifacts" if downloadable.empty?

      destination = Pathname.new(options[:directory]).expand_path
      FileUtils.mkdir_p(destination)
      downloaded = downloadable.map do |artifact|
        attributes = artifact.fetch("attributes")
        filename = File.basename(attributes.fetch("fileName"))
        path = destination.join(filename)
        raise ValidationError, "duplicate Xcode Cloud artifact name: #{filename}" if path.exist?
        @runner.run(
          "/usr/bin/curl", "--fail", "--location", "--retry", "3", "--output", path, attributes.fetch("downloadUrl"),
          redact_arguments: [7]
        )
        reported_size = attributes["fileSize"]
        if reported_size
          begin
            expected_size = Integer(reported_size)
          rescue ArgumentError, TypeError
            raise ValidationError, "Xcode Cloud reported a malformed size for #{filename}"
          end
          if File.size(path) != expected_size
            raise ValidationError, "Xcode Cloud artifact size mismatch for #{filename}"
          end
        end
        {
          "id" => artifact.fetch("id"),
          "file_name" => filename,
          "file_type" => attributes["fileType"],
          "file_size" => attributes["fileSize"],
          "path" => path.to_s,
          "sha256" => Digest::SHA256.file(path).hexdigest
        }
      end
      emit({ "run_id" => options[:run_id], "artifacts" => downloaded }, options[:output])
    end

    def retry_alpha(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release retry-alpha --failed-run-id ID --workflow-id ID --tag TAG --commit SHA"
        value.on("--failed-run-id ID") { |item| options[:failed_run_id] = item }
        value.on("--workflow-id ID") { |item| options[:workflow_id] = item }
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--commit SHA") { |item| options[:commit] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :failed_run_id, :workflow_id, :tag, :commit)

      client = app_store_client
      failed = client.build_run(options[:failed_run_id])
      raise ValidationError, "failed Alpha run belongs to a different workflow" unless failed["workflow_id"] == options[:workflow_id]
      raise ValidationError, "failed Alpha run belongs to a different tag" unless failed["git_reference"] == options[:tag]
      commits = [failed["source_commit"], failed["destination_commit"]].compact
      raise ValidationError, "failed Alpha run belongs to a different commit" unless commits.include?(options[:commit])
      unless failed["execution_progress"] == "COMPLETE" && failed["completion_status"] != "SUCCEEDED"
        raise ValidationError, "Alpha retry requires a completed unsuccessful run"
      end

      latest = client.find_cloud_run(
        workflow_id: options[:workflow_id],
        commit: options[:commit],
        tag: options[:tag]
      )
      if latest && latest["id"] != failed["id"]
        if latest["execution_progress"] == "COMPLETE" && latest["completion_status"] != "SUCCEEDED"
          raise ValidationError, "a newer unsuccessful Alpha run exists; authorize that exact run ID"
        end
        return emit(latest.merge(
          "retried_failed_run_id" => failed.fetch("id"),
          "reused_existing_retry" => true
        ), options[:output])
      end

      reference_id = failed["git_reference_id"]
      raise ValidationError, "failed Alpha run has no source tag relationship" if reference_id.to_s.empty?
      started = client.start_cloud_run(
        workflow_id: options[:workflow_id],
        git_reference_id: reference_id
      )
      emit({
        "id" => started.fetch("id"),
        "workflow_id" => options[:workflow_id],
        "git_reference" => options[:tag],
        "source_commit" => options[:commit],
        "retried_failed_run_id" => failed.fetch("id"),
        "reused_existing_retry" => false
      }, options[:output])
    end

    def submit(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release submit --manifest FILE --notes FILE --confirm 'SUBMIT VERSION (BUILD)' [--integrity-failure-marker FILE]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--notes FILE") { |item| options[:notes] = item }
        value.on("--confirm TEXT") { |item| options[:confirm] = item }
        value.on("--schedule-at TIME") { |item| options[:schedule_at] = Time.parse(item) }
        value.on("--integrity-failure-marker FILE") { |item| options[:integrity_failure_marker] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest, :notes, :confirm)

      manifest = Manifest.read(options[:manifest])
      data = manifest.to_h
      raise ValidationError, "customer App Store submission is production-only" unless data["channel"] == "production"
      version = data.fetch("target_version")
      build = data.fetch("canonical_build")
      expected_confirmation = "SUBMIT #{version} (#{build})"
      raise ValidationError, "submission confirmation must be exactly #{expected_confirmation.inspect}" unless options[:confirm] == expected_confirmation

      notes = File.read(options[:notes]).strip
      raise ValidationError, "App Store release notes must not be empty" if notes.empty?
      raise ValidationError, "App Store release notes exceed Apple's 4,000 character limit" if notes.length > 4_000
      schedule_threshold = Time.now + (72 * 60 * 60) + SUBMISSION_SCHEDULE_SAFETY_SECONDS
      scheduled = options[:schedule_at] || default_schedule_time(Time.now + SUBMISSION_SCHEDULE_SAFETY_SECONDS)
      if scheduled < schedule_threshold
        raise ValidationError, "scheduled release must remain at least 72 hours in the future through submission"
      end

      client = app_store_client
      previous = client.latest_released_version(app_id: Config::PRODUCTION_APP_ID)
      raise ValidationError, "could not locate the current live production version" unless previous
      previous_localization = client.localization(version_id: previous.fetch("id"))
      promotional_text = previous_localization&.dig("attributes", "promotionalText").to_s.strip
      raise ValidationError, "current production Promotional Text is empty" if promotional_text.empty?

      Dir.mktmpdir("sequel-ace-app-store-submit") do |temporary_directory|
        promotion_file = File.join(temporary_directory, "promotional_text.txt")
        File.write(promotion_file, promotional_text)
        validate_submission_handoff!(manifest: manifest, notes: notes)
        fastlane_release_stage(
          version: version,
          build: build,
          notes_file: options[:notes],
          promotion_file: promotion_file,
          scheduled: scheduled
        )

        refreshed_threshold = Time.now + (72 * 60 * 60) + SUBMISSION_SCHEDULE_SAFETY_SECONDS
        if scheduled < refreshed_threshold
          if options[:schedule_at]
            raise ValidationError, "explicit release schedule became too close during metadata staging"
          end
          scheduled = default_schedule_time(Time.now + SUBMISSION_SCHEDULE_SAFETY_SECONDS)
          validate_submission_handoff!(manifest: manifest, notes: notes)
          fastlane_release_stage(
            version: version,
            build: build,
            notes_file: options[:notes],
            promotion_file: promotion_file,
            scheduled: scheduled
          )
        end

        snapshot = wait_for_metadata(client, version)
        exact_build = client.find_build(app_id: Config::PRODUCTION_APP_ID, version: version, build: build)
        raise ValidationError, "exact App Store Connect build #{version} (#{build}) is unavailable" unless exact_build
        validate_submission_handoff!(manifest: manifest, notes: notes)
        client.attach_build(version_id: snapshot.dig("version", "id"), build_id: exact_build.fetch("id"))
        snapshot = wait_for_selected_build(client, version, build)
        minimum = Time.now + (72 * 60 * 60)
        MetadataValidator.new.validate!(
          snapshot: snapshot,
          expected_build: build,
          expected_notes: notes,
          expected_promotional_text: promotional_text,
          minimum_release_time: minimum
        )
        validate_submission_handoff!(manifest: manifest, notes: notes)
        fastlane_release_submit(version: version, build: build)
        final_snapshot = wait_for_submission_state(client, version)
        MetadataValidator.new.validate!(
          snapshot: final_snapshot,
          expected_build: build,
          expected_notes: notes,
          expected_promotional_text: promotional_text,
          minimum_release_time: minimum
        )
        emit({
          "version_id" => final_snapshot.dig("version", "id"),
          "build_id" => final_snapshot.dig("selected_build", "id"),
          "app_store_state" => MetadataValidator.app_version_state(final_snapshot.fetch("version")),
          "scheduled_release_at" => scheduled.utc.iso8601,
          "phased_release_state" => final_snapshot.dig("phased_release", "attributes", "phasedReleaseState")
        }, options[:output])
      end
    rescue IntegrityError
      write_integrity_failure_marker(options[:integrity_failure_marker])
      raise
    end

    def create_manifest(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release create-manifest --approval FILE --approval-sha SHA --reconciliation FILE --release-plan FILE --base-sha SHA --output FILE"
        value.on("--approval FILE") { |item| options[:approval] = item }
        value.on("--approval-sha SHA") { |item| options[:approval_sha] = item }
        value.on("--reconciliation FILE") { |item| options[:reconciliation] = item }
        value.on("--release-plan FILE") { |item| options[:release_plan] = item }
        value.on("--base-sha SHA") { |item| options[:base_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :approval, :approval_sha, :reconciliation, :release_plan, :base_sha, :output)

      release_approval = approval_from_file(options[:approval])
      release_approval.verify!(options[:approval_sha])
      reconciliation = read_json(options[:reconciliation])
      plan_data = read_json(options[:release_plan])
      naming = ReleaseNaming.new(
        channel: release_approval.payload.fetch("channel"),
        version: release_approval.payload.fetch("target_version"),
        build: reconciliation.fetch("target_build"),
        iteration: plan_data.fetch("iteration")
      )
      manifest = Manifest.create(
        approval: release_approval,
        naming: naming,
        base_sha: options[:base_sha],
        canonical_build: reconciliation.fetch("target_build"),
        production_build_evidence: reconciliation.fetch("production_build_evidence"),
        skipped_production_builds: reconciliation.fetch("skipped_production_builds", []),
        release_notes_sha256: plan_data.fetch("release_notes_sha256")
      )
      manifest.write(options[:output])
      emit(manifest.to_h)
    end

    def update_manifest(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release update-manifest --manifest FILE --state STATE [--merge FILE]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--state STATE") { |item| options[:state] = item }
        value.on("--merge FILE") { |item| options[:merge] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest, :state)
      manifest = Manifest.read(options[:manifest])
      updates = options[:merge] ? read_json(options[:merge]) : {}
      updates["state"] = options[:state]
      updated = manifest.with(updates)
      destination = options[:output] || options[:manifest]
      updated.write(destination)
      emit(updated.to_h)
    end

    def reconcile_submission(arguments)
      options = { wait_seconds: 0, poll_interval: 15 }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release reconcile-submission --manifest FILE [--wait-seconds SECONDS] [--poll-interval SECONDS]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--wait-seconds SECONDS", Integer) { |item| options[:wait_seconds] = item }
        value.on("--poll-interval SECONDS", Integer) { |item| options[:poll_interval] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest)
      manifest = Manifest.read(options[:manifest])
      result = SubmissionReconciler.new(client: app_store_client).reconcile(
        manifest,
        timeout_seconds: options[:wait_seconds],
        interval_seconds: options[:poll_interval]
      )
      emit(result, options[:output])
    end

    def record_failure(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release record-failure --manifest FILE --workflow-url URL [--submission FILE]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--workflow-url URL") { |item| options[:workflow_url] = item }
        value.on("--submission FILE") { |item| options[:submission] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest, :workflow_url)
      manifest = Manifest.read(options[:manifest])
      submission = read_json(options[:submission]) if options[:submission]
      result = FailureRecorder.new.record(
        manifest: manifest,
        workflow_url: options[:workflow_url],
        submission: submission
      )
      result.manifest.write(options[:manifest])
      emit(result.to_h, options[:output])
    end

    def finalize(arguments)
      options = { validate_only: false }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release finalize --manifest FILE --confirm 'FINALIZE TAG' [--validate-only] [--integrity-failure-marker FILE]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--confirm TEXT") { |item| options[:confirm] = item }
        value.on("--validate-only") { options[:validate_only] = true }
        value.on("--integrity-failure-marker FILE") { |item| options[:integrity_failure_marker] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest, :confirm)

      manifest = Manifest.read(options[:manifest])
      data = manifest.to_h
      raise ValidationError, "beta releases are never finalized" unless data["channel"] == "production"
      expected_confirmation = "FINALIZE #{data.fetch('tag')}"
      raise ValidationError, "finalization confirmation must be exactly #{expected_confirmation.inspect}" unless options[:confirm] == expected_confirmation

      apple = app_store_client
      snapshot = apple.metadata_snapshot(
        app_id: Config::PRODUCTION_APP_ID,
        version: data.fetch("target_version")
      )
      MetadataValidator.new.validate!(
        snapshot: snapshot,
        expected_build: data.fetch("canonical_build"),
        require_live: true
      )
      latest = apple.latest_released_version(app_id: Config::PRODUCTION_APP_ID)
      unless latest.is_a?(Hash) && latest["id"] == snapshot.dig("version", "id")
        raise ValidationError, "App Store version is not the latest released Production version"
      end

      client = github_client
      archived_commit = data.fetch("release_commit_sha")
      current_tag_commit = client.ref_sha("tags/#{data.fetch('tag')}")
      unless current_tag_commit == archived_commit
        raise ValidationError,
              "release tag moved after archival (expected #{archived_commit}, found #{current_tag_commit})"
      end
      release = client.release_by_tag(data.fetch("tag"))
      unless release["tag_name"] == data.fetch("tag") && release["draft"] == false
        raise ValidationError, "GitHub release identity is not publishable"
      end
      ReleasePublisher.validate!(
        tag: data.fetch("tag"),
        login: release.dig("author", "login"),
        id: release.dig("author", "id")
      )
      verify_release_assets!(release, data, github: client)
      final_title = ReleaseNaming.new(
        channel: "production",
        version: data.fetch("target_version"),
        build: data.fetch("canonical_build"),
        iteration: data.fetch("iteration")
      ).final_title
      current_latest = begin
        client.latest_release
      rescue APIError => error
        raise unless error.status == 404

        nil
      end
      currently_latest = !current_latest.nil? && current_latest["id"] == release["id"] &&
                         current_latest["tag_name"] == data.fetch("tag")
      transition_required = release["prerelease"] != false || release["name"] != final_title || !currently_latest
      evidence = {
        "release_id" => release.fetch("id"),
        "tag" => data.fetch("tag"),
        "release_commit_sha" => archived_commit,
        "app_store_state" => "READY_FOR_DISTRIBUTION",
        "current_title" => release["name"],
        "current_draft" => release["draft"],
        "current_prerelease" => release["prerelease"],
        "current_latest" => currently_latest,
        "target_title" => final_title,
        "target_latest" => true,
        "transition_required" => transition_required
      }
      if options[:validate_only]
        return emit(evidence.merge("github_transition" => "durably_validated_before_public_transition"), options[:output])
      end

      if transition_required
        client.update_release(
          id: release.fetch("id"),
          tag: data.fetch("tag"),
          target_sha: archived_commit,
          title: final_title,
          prerelease: false,
          make_latest: true
        )
      end
      finalized_tag_commit = client.ref_sha("tags/#{data.fetch('tag')}")
      unless finalized_tag_commit == archived_commit
        raise ValidationError,
              "release tag moved during finalization (expected #{archived_commit}, found #{finalized_tag_commit})"
      end
      release = client.release_by_tag(data.fetch("tag"))
      unless release["id"] == evidence.fetch("release_id") && release["tag_name"] == data.fetch("tag") &&
             release["name"] == final_title && release["draft"] == false && release["prerelease"] == false &&
             ReleasePublisher.authorized?(
               tag: data.fetch("tag"),
               login: release.dig("author", "login"),
               id: release.dig("author", "id")
             )
        raise ValidationError, "GitHub finalization readback did not match the requested release"
      end
      post_transition_assets = verify_release_assets!(release, data, github: client)
      latest_release = client.latest_release
      unless latest_release["id"] == release["id"] && latest_release["tag_name"] == data.fetch("tag") &&
             latest_release["name"] == final_title && latest_release["draft"] == false &&
             latest_release["prerelease"] == false
        raise ValidationError, "GitHub did not mark the finalized release as latest"
      end
      emit(evidence.merge(
        "github_transition" => "complete",
        "final_title" => release["name"],
        "final_draft" => release["draft"],
        "final_prerelease" => release["prerelease"],
        "final_latest" => true,
        "post_transition_public_feed" => post_transition_assets.fetch("release_feed_verification")
      ), options[:output])
    rescue IntegrityError
      write_integrity_failure_marker(options[:integrity_failure_marker])
      raise
    end

    def validate_submission_handoff!(manifest:, notes:)
      client = github_client
      data = manifest.to_h
      result = PublishHandoff.new(github: client).validate(
        manifest: manifest,
        tag: data.fetch("tag"),
        app_store_notes: notes
      )
      unless result.fetch("eligible") && result.fetch("state") == "archived"
        raise ValidationError, "production submission requires an eligible archived GitHub handoff"
      end

      release = client.release_by_tag(data.fetch("tag"))
      unless release["id"] == result.fetch("github_release_id") &&
             release["tag_name"] == data.fetch("tag") &&
             release["name"] == data.fetch("title") &&
             release["draft"] == false && release["prerelease"] == true
        raise IntegrityError, "GitHub release identity changed during App Store submission"
      end
      ReleasePublisher.validate!(
        tag: data.fetch("tag"),
        login: release.dig("author", "login"),
        id: release.dig("author", "id")
      )
      status = verify_release_assets!(release, data, github: client)
      if status.key?("release_feed_entries_verified")
        result["release_feed_entries_verified"] = status.fetch("release_feed_entries_verified")
      end
      result["compatibility_profile"] = status.fetch("compatibility_profile")
      result
    end

    def github_client(optional: false)
      token = @env["SA_GITHUB_TOKEN"] || @env["GH_TOKEN"] || @env["GITHUB_TOKEN"]
      return nil if optional && token.to_s.empty?

      GitHubClient.new(token: token)
    end

    def github_user_publisher_client
      token = ReleasePublisher.validate_user_publisher_token!(
        @env["SA_RELEASE_GITHUB_PUBLISHER_TOKEN"]
      )
      GitHubClient.new(token: token)
    end

    def app_store_client
      AppStoreConnectClient.from_env(@env)
    end

    def emit(value, path = nil)
      rendered = CanonicalJSON.pretty(value)
      if path
        File.write(path, rendered)
      else
        @out.write(rendered)
      end
      value
    end

    def read_json(path)
      JSON.parse(File.read(path))
    end

    def validate_forward_recovery_pr_evidence!(recovery, approval:, approval_sha:, expected_sha:, requested_build:)
      failed_build = recovery["failed_expected_build"]
      expected_predecessor_tag = if failed_build.is_a?(Integer) && failed_build.positive?
                                   "#{approval.payload.fetch('channel')}/#{approval.payload.fetch('target_version')}-#{failed_build}"
                                 end
      valid = recovery["predecessor_release_commit_sha"] == expected_sha &&
              recovery["predecessor_tag"] == expected_predecessor_tag &&
              recovery["approval_sha256"] == approval_sha &&
              recovery["expected_recovery_build"].is_a?(Integer) &&
              recovery["expected_recovery_build"].positive? &&
              recovery["expected_recovery_build"] == requested_build
      raise ValidationError, "forward-recovery evidence does not match the requested release PR" unless valid
    end

    def approval_from_file(path)
      value = read_json(path)
      value = value.fetch("approval") if value.key?("approval")
      value = value.reject { |key, _| key == "sha256" }
      Approval.from_hash(value)
    end

    def reject_arguments!(arguments)
      raise OptionParser::InvalidArgument, "unexpected arguments: #{arguments.join(' ')}" unless arguments.empty?
    end

    def require_options!(options, *keys)
      missing = keys.select { |key| options[key].nil? || options[key].respond_to?(:empty?) && options[key].empty? }
      raise OptionParser::MissingArgument, missing.join(", ") unless missing.empty?
    end

    def validate_preparation_paths!(paths)
      allowed = release_paths
      renamed_or_copied = paths.select { |entry| entry.fetch("status").start_with?("R", "C") }
      unless renamed_or_copied.empty?
        raise ValidationError, "release preparation must not rename or copy release files"
      end
      changed = paths.map { |entry| entry.fetch("path") }
      original = paths.filter_map { |entry| entry["original_path"] }
      unexpected = (changed + original).uniq - allowed
      raise ValidationError, "release preparation changed unauthorized paths: #{unexpected.join(', ')}" unless unexpected.empty?
      raise ValidationError, "release preparation did not update CHANGELOG.md" unless changed.include?("CHANGELOG.md")
      missing = (Config::PROJECT_FILES.keys + Config::PLIST_FILES) - changed
      raise ValidationError, "release preparation did not update required version files: #{missing.join(', ')}" unless missing.empty?
    end

    def release_paths
      Config::PROJECT_FILES.keys + Config::PLIST_FILES + ["CHANGELOG.md"]
    end

    def highest_build_from_tags(tags)
      tags.filter_map { |tag| tag[%r{\A(?:production|beta)/\d+\.\d+\.\d+-([1-9]\d*)\z}, 1]&.to_i }.max || 0
    end

    def recover_release_tag(options:, git:, source_build:, source_release_commit_sha:, runs:, app_store_client:)
      channel = options[:recover_release_channel]
      version = options[:recover_release_version]
      return nil if channel.nil? && version.nil?
      if channel.to_s.empty? || version.to_s.empty?
        raise ValidationError, "tag-only recovery requires both release channel and version"
      end

      naming = ReleaseNaming.new(channel: channel, version: version, build: source_build, iteration: 1)
      tag = naming.tag
      return nil unless git.tag_exists?(tag)
      unless Config.valid_git_sha?(source_release_commit_sha) && git.sha("refs/tags/#{tag}") == source_release_commit_sha
        raise IntegrityError, "tag-only recovery tag does not resolve to the exact release preparation commit"
      end

      begin
        github_client.release_by_tag(tag)
        return nil
      rescue APIError => error
        raise unless error.status == 404
      end
      if options[:workflow_id].to_s.empty? || app_store_client.nil?
        raise ValidationError, "tag-only recovery requires Production Xcode Cloud access"
      end

      run = Array(runs).find { |candidate| candidate["number"].to_i == source_build }
      if run
        details = app_store_client.build_run(run.fetch("id"))
        run.replace(run.merge(details))
      end
      tag
    end

    def release_pull_request_body(naming, release_body)
      <<~BODY
        ## Changes:
        - Prepare #{naming.channel} release #{naming.version} (#{naming.build}).
        - Set the explicit Xcode Cloud-authoritative build number in every versioned project and plist.
        - Regenerate the changelog from the approved cumulative changelog base.

        ## Closes following issues:
        - Closes: N/A

        ## Tested:
        - Processors:
          - [ ] Intel
          - [ ] Apple Silicon
        - macOS Versions:
          - [ ] 13.5+ (Ventura)
          - [ ] 14.x (Sonoma)
          - [ ] 15.x (Sequoia)
          - [ ] 26.x (Tahoe)
          - [ ] 27.x (Golden Gate)
        - Localizations:
          - [x] English release metadata generated
          - [ ] Spanish
          - [ ] Other (please specify)
        - Xcode Version: CI-controlled

        ## Screenshots:
        - No screenshot changes.

        ## Additional notes:
        - Release branch: `#{naming.branch}`
        - Tag after merge: `#{naming.tag}`
        - The deployment workflow must wait for every required exact-head check before merging.

        #{release_body}
      BODY
    end

    def default_schedule_time(now = Time.now)
      threshold = now + (72 * 60 * 60)
      old_timezone = ENV["TZ"]
      ENV["TZ"] = "America/Los_Angeles"
      local_threshold = Time.at(threshold.to_i)
      date = local_threshold.to_date
      candidate = Time.local(date.year, date.month, date.day, 9, 0, 0)
      if candidate < threshold
        date += 1
        candidate = Time.local(date.year, date.month, date.day, 9, 0, 0)
      end
      candidate
    ensure
      old_timezone.nil? ? ENV.delete("TZ") : ENV["TZ"] = old_timezone
    end

    def fastlane_release_stage(version:, build:, notes_file:, promotion_file:, scheduled:)
      @runner.run(
        bundle_executable,
        "exec", "fastlane", "mac", "stage_app_store_release",
        "version:#{version}",
        "build:#{build}",
        "release_notes_file:#{File.expand_path(notes_file)}",
        "promotional_text_file:#{File.expand_path(promotion_file)}",
        "auto_release_date:#{scheduled.to_i * 1_000}"
      )
    end

    def fastlane_release_submit(version:, build:)
      @runner.run(
        bundle_executable,
        "exec", "fastlane", "mac", "submit_app_store_release",
        "version:#{version}",
        "build:#{build}"
      )
    end

    def bundle_executable
      @env["BUNDLE_BIN"] || "bundle"
    end

    def wait_for_metadata(client, version, timeout: 900)
      deadline = Time.now + timeout
      loop do
        begin
          return client.metadata_snapshot(app_id: Config::PRODUCTION_APP_ID, version: version)
        rescue ValidationError, APIError
          raise if Time.now >= deadline

          sleep(15)
        end
      end
    end

    def wait_for_selected_build(client, version, build, timeout: 900)
      deadline = Time.now + timeout
      loop do
        snapshot = client.metadata_snapshot(app_id: Config::PRODUCTION_APP_ID, version: version)
        return snapshot if snapshot.dig("selected_build", "attributes", "version").to_s == build.to_s
        raise ValidationError, "timed out attaching App Store build #{build}" if Time.now >= deadline

        sleep(15)
      end
    end

    def wait_for_submission_state(client, version, timeout: 900)
      deadline = Time.now + timeout
      loop do
        snapshot = client.metadata_snapshot(app_id: Config::PRODUCTION_APP_ID, version: version)
        state = MetadataValidator.app_version_state(snapshot.fetch("version"))
        return snapshot if SUBMITTED_APP_STORE_STATES.include?(state)
        raise ValidationError, "App Store submission entered #{state}" if FAILED_APP_STORE_STATES.include?(state)
        raise ValidationError, "timed out confirming App Store review submission (state: #{state || 'unknown'})" if Time.now >= deadline

        sleep(15)
      end
    end

    def verify_release_assets!(release, manifest, github:)
      actual_notes_sha = Digest::SHA256.hexdigest(release.fetch("body").to_s)
      unless actual_notes_sha == manifest.fetch("release_notes_sha256")
        raise IntegrityError, "GitHub release notes no longer match the archived manifest"
      end

      validator = GitHubReleasePayload.new(
        release: release,
        expected_digests: release_asset_sha256s!(manifest)
      )
      status = validator.validate
      unless status.fetch("ready")
        raise IntegrityError,
              "GitHub release is missing artifacts: #{status.fetch('missing_assets').join(', ')}"
      end
      status["release_feed_entries_verified"] = validator.validate_public_feed!(github.public_release_feed_page)
      status["release_feed_verification"] = "verified"
      status
    end

    def release_asset_sha256s!(manifest)
      expected_names = Array(manifest.fetch("artifact_names"))
      verification = manifest.fetch("verification", {})
      expected_digests = verification.each_with_object({}) do |(_key, value), result|
        next unless value.is_a?(Hash) && value["zip_path"] && value["zip_sha256"]

        name = File.basename(value["zip_path"])
        raise IntegrityError, "private manifest has duplicate artifact checksums for #{name}" if result.key?(name)

        result[name] = value["zip_sha256"].to_s.downcase
      end
      missing_digests = expected_names - expected_digests.keys
      unless missing_digests.empty?
        raise IntegrityError, "private manifest is missing artifact checksums: #{missing_digests.join(', ')}"
      end
      unexpected_digests = expected_digests.keys - expected_names
      unless unexpected_digests.empty?
        raise IntegrityError, "private manifest has unexpected artifact checksums: #{unexpected_digests.join(', ')}"
      end
      expected_digests
    end

    def verified_release_asset_sha256!(manifest:, path:, name:)
      data = manifest.to_h
      basename = File.basename(path)
      unless name == basename
        raise IntegrityError, "release asset name #{name} does not match local file #{basename}"
      end
      stat = File.lstat(path)
      unless stat.file? && !stat.symlink?
        raise IntegrityError, "release asset #{name} is not a regular non-symlink file"
      end

      expected_names = Array(data.fetch("artifact_names"))
      unless expected_names.count(name) == 1
        raise IntegrityError, "release asset #{name} is not a unique manifest-approved artifact"
      end

      matches = data.fetch("verification").values.select do |value|
        value.is_a?(Hash) && value["zip_path"].is_a?(String) &&
          File.basename(value["zip_path"]) == name && value["zip_sha256"]
      end
      unless matches.length == 1
        raise IntegrityError, "release asset #{name} does not have one manifest verification record"
      end

      digest = matches.fetch(0).fetch("zip_sha256").to_s.downcase
      unless digest.match?(/\A[0-9a-f]{64}\z/)
        raise IntegrityError, "release asset #{name} has a malformed manifest checksum"
      end
      unless Digest::SHA256.file(path).hexdigest == digest
        raise IntegrityError, "release asset #{name} does not match its manifest checksum"
      end

      digest
    rescue Errno::ENOENT, Errno::EACCES => error
      raise ValidationError, "release asset #{name} is not readable: #{error.class}"
    rescue KeyError, TypeError
      raise IntegrityError, "release asset verification evidence is malformed"
    end

    def write_integrity_failure_marker(path)
      return unless path

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "release asset integrity failure\n")
    rescue SystemCallError => error
      @err.puts("release tool warning: could not write integrity failure marker (#{error.class})")
    end

    def help
      <<~HELP
        Sequel Ace release infrastructure #{SequelAceRelease::VERSION}

        Commands:
          guard                      Enforce actor, ref, freeze, confirmation, and enable gates
          plan                       Create a read-only release plan and approval payload
          prepare                    Set explicit version/build values and regenerate CHANGELOG.md
          reconcile-build            Derive highest observed Production build plus one
          verify-artifact            Verify signing, notarization, architecture, metadata, and launch
          verify-artifact-set        Find and verify the distributable app in a Cloud artifact set
          submit                     Stage, validate, and submit a production App Store version
          finalize                   Finalize a GitHub prerelease after App Store release
          github-prepare-pr          Create a verified GitHub App release commit and PR
          github-cleanup-branch      Close and delete an exact failed release branch
          github-wait-checks         Wait for exact-head release PR checks
          github-merge-pr            Recheck and merge the release PR
          github-validate-release-target
                                     Prove a release commit remains an unchanged main ancestor
          github-verify-release-tag   Prove a release tag still names the exact release commit
          github-release-publisher-mode
                                     Select a live-capable initial release publisher
          github-create-release      Create the tag-backed GitHub prerelease
          github-public-assets-status
                                     Validate public assets and legacy-client metadata
          github-upload-asset        Upload a verified zip to the prerelease
          validate-publish-handoff   Validate an archived prerelease continuation
          validate-forward-recovery  Validate a preserved forward-only build mismatch
          cloud-status               Inspect an exact Xcode Cloud build without waiting
          wait-cloud                 Wait for an exact Xcode Cloud build
          download-cloud-artifacts   Download every artifact for an exact Cloud build run
          retry-alpha                Reuse or start an Alpha-only retry for a failed beta run
          create-manifest            Create the versioned non-secret release manifest
          update-manifest            Advance a manifest with redacted run evidence
          reconcile-submission       Read back an ambiguous production App Store submission
          record-failure             Preserve finalizable state while recording a failed run
      HELP
    end
  end
end
