# frozen_string_literal: true

require "base64"
require "date"
require "fileutils"
require "optparse"

module SequelAceRelease
  class CLI
    SUBMISSION_SCHEDULE_SAFETY_SECONDS = 15 * 60
    SUBMITTED_APP_STORE_STATES = SubmissionReconciler::SUBMITTED_STATES
    FAILED_APP_STORE_STATES = %w[
      DEVELOPER_REJECTED INVALID_BINARY METADATA_REJECTED REJECTED
    ].freeze

    def self.run(argv, out: $stdout, err: $stderr, env: ENV)
      new(out: out, err: err, env: env).run(argv)
    end

    def initialize(out:, err:, env:)
      @out = out
      @err = err
      @env = env
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
      when "github-create-release" then github_create_release(argv)
      when "github-upload-asset" then github_upload_asset(argv)
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
        value.banner = "Usage: sa-release guard --actor LOGIN --ref REF --current-sha SHA --expected-sha SHA --channel CHANNEL --version VERSION --cloud-next-build BUILD --confirmation TEXT --enabled VALUE"
        value.on("--actor LOGIN") { |item| options[:actor] = item }
        value.on("--ref REF") { |item| options[:ref] = item }
        value.on("--current-sha SHA") { |item| options[:current_sha] = item }
        value.on("--expected-sha SHA") { |item| options[:expected_sha] = item }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--cloud-next-build BUILD", Integer) { |item| options[:cloud_next_build] = item }
        value.on("--confirmation TEXT") { |item| options[:confirmation] = item }
        value.on("--enabled VALUE") { |item| options[:enabled] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :actor, :ref, :current_sha, :expected_sha, :channel, :version, :cloud_next_build, :confirmation, :enabled)
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
        value.on("--observed-cloud-next-build BUILD", Integer) { |item| options[:observed_cloud_next_build] = item }
        value.on("--expected-approval-sha SHA") { |item| options[:expected_approval_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :observed_cloud_next_build)

      github = github_client(optional: true)
      result = Planner.new(github: github).plan(**options.slice(
        :channel, :target_version, :base_tag, :main_ref, :app_store_notes, :observed_cloud_next_build
      ))
      if options[:expected_approval_sha]
        Approval.from_hash(result.fetch("approval")).verify!(options[:expected_approval_sha])
      end
      emit(result, options[:output])
    end

    def prepare(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release prepare --version VERSION --build BUILD --base-tag TAG [options]"
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--base-tag TAG") { |item| options[:base_tag] = item }
        value.on("--expected-main-sha SHA") { |item| options[:expected_main_sha] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :version, :build, :channel, :base_tag)
      Config.validate_channel!(options[:channel])

      git = GitRepository.new
      git.ensure_clean!
      current_sha = git.sha
      if options[:expected_main_sha] && current_sha != options[:expected_main_sha]
        raise ValidationError, "HEAD #{current_sha} does not match frozen main #{options[:expected_main_sha]}"
      end
      raise ValidationError, "base tag does not resolve" if git.sha(options[:base_tag]).empty?

      version_result = VersionFiles.new.update!(version: options[:version], build: options[:build])
      @runner.run(
        Config.repo_root.join("Scripts/generate-changelog.sh"),
        options[:version],
        env: { "RANGE_START" => options[:base_tag], "RANGE_END" => current_sha }
      )
      changed_paths = git.changed_paths
      validate_preparation_paths!(changed_paths)
      emit({
        "channel" => options[:channel],
        "head_sha" => current_sha,
        "base_tag" => options[:base_tag],
        "versions" => version_result,
        "changed_paths" => changed_paths
      }, options[:output])
    end

    def reconcile_build(arguments)
      options = { cloud_runs: [] }
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release reconcile-build --cloud-next-build BUILD [options]"
        value.on("--source-build BUILD", Integer) { |item| options[:source_build] = item }
        value.on("--highest-tag-build BUILD", Integer) { |item| options[:highest_tag_build] = item }
        value.on("--highest-asc-build BUILD", Integer) { |item| options[:highest_asc_build] = item }
        value.on("--cloud-next-build BUILD", Integer) { |item| options[:cloud_next_build] = item }
        value.on("--cloud-runs FILE") { |item| options[:cloud_runs] = read_json(item) }
        value.on("--workflow-id ID") { |item| options[:workflow_id] = item }
        value.on("--source-tagged") { options[:source_tagged] = true }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :cloud_next_build)

      git = GitRepository.new
      source_build = options[:source_build] || VersionFiles.new.current.fetch("build")
      highest_tag = options[:highest_tag_build] || highest_build_from_tags(git.tags("production/*"))
      asc_client = nil
      if options[:workflow_id] || !options.key?(:highest_asc_build)
        asc_client = app_store_client
      end
      runs = options[:workflow_id] ? asc_client.workflow_runs(options[:workflow_id]) : Array(options[:cloud_runs])
      highest_asc = options.fetch(:highest_asc_build) { asc_client.highest_app_build(Config::PRODUCTION_APP_ID) }
      source_tags = git.tags("production/*-#{source_build}") + git.tags("beta/*-#{source_build}")
      source_tagged = options.fetch(:source_tagged, false) || source_tags.any?
      required_release_paths = Config::PROJECT_FILES.keys + Config::PLIST_FILES + ["CHANGELOG.md"]

      result = BuildReconciler.new.reconcile(
        source_build: source_build,
        highest_tag_build: highest_tag,
        highest_asc_build: highest_asc,
        cloud_next_build: options[:cloud_next_build],
        cloud_runs: runs,
        source_tagged: source_tagged,
        source_is_release_tip: git.head_changes_all?(required_release_paths)
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
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :approval_file, :approval_sha, :build, :release_body)

      approval = approval_from_file(options[:approval_file])
      approval.verify!(options[:approval_sha])
      git = GitRepository.new
      expected_sha = approval.payload.fetch("main_sha")
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
            expected_sha256: artifact["sha256"]
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
        value.banner = "Usage: sa-release github-create-release --channel CHANNEL --version VERSION --build BUILD --target-sha SHA --body FILE"
        value.on("--channel CHANNEL") { |item| options[:channel] = item }
        value.on("--version VERSION") { |item| options[:version] = item }
        value.on("--build BUILD", Integer) { |item| options[:build] = item }
        value.on("--iteration NUMBER", Integer) { |item| options[:iteration] = item }
        value.on("--target-sha SHA") { |item| options[:target_sha] = item }
        value.on("--body FILE") { |item| options[:body] = File.read(item) }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :channel, :version, :build, :target_sha, :body)
      naming = ReleaseNaming.new(**options.slice(:channel, :version, :build, :iteration))
      client = github_client
      current_main = client.ref_sha
      unless current_main == options[:target_sha]
        raise ValidationError, "main changed before release tagging (expected #{options[:target_sha]}, found #{current_main})"
      end
      release = client.create_release(
        tag: naming.tag,
        target_sha: options[:target_sha],
        title: naming.title,
        body: options[:body]
      )
      emit({ "naming" => naming.to_h, "release" => release }, options[:output])
    end

    def github_upload_asset(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release github-upload-asset --tag TAG --file FILE [--name NAME]"
        value.on("--tag TAG") { |item| options[:tag] = item }
        value.on("--run-id ID") { |item| options[:run_id] = item }
        value.on("--file FILE") { |item| options[:file] = item }
        value.on("--name NAME") { |item| options[:name] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :tag, :file)
      client = github_client
      release = client.release_by_tag(options[:tag])
      response = client.upload_release_asset(
        release: release,
        path: options[:file],
        name: options[:name] || File.basename(options[:file])
      )
      emit(response, options[:output])
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

      client = app_store_client
      deadline = Time.now + options[:timeout]
      loop do
        run = client.find_cloud_run(
          workflow_id: options[:workflow_id],
          build: options[:build],
          commit: options[:commit],
          tag: options[:tag],
          run_id: options[:run_id]
        )
        if run
          status = run["completion_status"]
          if run["execution_progress"] == "COMPLETE"
            label = options[:build] || run["number"]
            raise ValidationError, "Xcode Cloud build #{label} completed with #{status}" unless status == "SUCCEEDED"
            cloud_builds = begin
              client.cloud_builds_for_run(run.fetch("id"))
            rescue APIError => error
              raise unless error.message.include?("HTTP 404")

              []
            end
            matching_build = cloud_builds.find do |candidate|
              next false unless candidate["app_id"] == options[:app_id]
              next false unless candidate["version"] == options[:version]
              next false if options[:build] && candidate["build"] != options[:build]

              true
            end
            if matching_build
              return emit(run.merge(
                "app_store_build_id" => matching_build.fetch("id"),
                "app_version" => matching_build.fetch("version"),
                "app_build" => matching_build.fetch("build")
              ), options[:output])
            end
            unless cloud_builds.empty?
              observed = cloud_builds.map { |candidate| candidate.slice("app_id", "version", "build") }
              raise ValidationError, "Xcode Cloud run does not contain the expected app version/build (observed: #{observed})"
            end
          end
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
        return emit(latest.merge("reused_existing_retry" => true), options[:output])
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
        "reused_existing_retry" => false
      }, options[:output])
    end

    def submit(arguments)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release submit --manifest FILE --notes FILE --confirm 'SUBMIT VERSION (BUILD)'"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--notes FILE") { |item| options[:notes] = item }
        value.on("--confirm TEXT") { |item| options[:confirm] = item }
        value.on("--schedule-at TIME") { |item| options[:schedule_at] = Time.parse(item) }
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
      Approval.new(
        channel: "production",
        target_version: version,
        main_sha: data.fetch("main_sha"),
        previous_tag: data.fetch("base_tag"),
        app_store_notes: notes,
        observed_production_cloud_next_build: data.fetch("observed_production_cloud_next_build")
      )
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
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: sa-release reconcile-submission --manifest FILE"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--output FILE") { |item| options[:output] = item }
      end
      parser.parse!(arguments)
      reject_arguments!(arguments)
      require_options!(options, :manifest)
      manifest = Manifest.read(options[:manifest])
      result = SubmissionReconciler.new(client: app_store_client).reconcile(manifest)
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
        value.banner = "Usage: sa-release finalize --manifest FILE --confirm 'FINALIZE TAG' [--validate-only]"
        value.on("--manifest FILE") { |item| options[:manifest] = item }
        value.on("--confirm TEXT") { |item| options[:confirm] = item }
        value.on("--validate-only") { options[:validate_only] = true }
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

      snapshot = app_store_client.metadata_snapshot(
        app_id: Config::PRODUCTION_APP_ID,
        version: data.fetch("target_version")
      )
      MetadataValidator.new.validate!(
        snapshot: snapshot,
        expected_build: data.fetch("canonical_build"),
        require_live: true
      )

      client = github_client
      release = client.release_by_tag(data.fetch("tag"))
      verify_release_assets!(release, data)
      final_title = ReleaseNaming.new(
        channel: "production",
        version: data.fetch("target_version"),
        build: data.fetch("canonical_build"),
        iteration: data.fetch("iteration")
      ).final_title
      transition_required = release["prerelease"] == true || release["name"] != final_title
      evidence = {
        "release_id" => release.fetch("id"),
        "tag" => data.fetch("tag"),
        "app_store_state" => "READY_FOR_DISTRIBUTION",
        "current_title" => release["name"],
        "current_prerelease" => release["prerelease"],
        "target_title" => final_title,
        "target_latest" => true,
        "transition_required" => transition_required
      }
      if options[:validate_only]
        return emit(evidence.merge("github_transition" => "durably_validated_before_public_transition"), options[:output])
      end

      if transition_required
        release = client.update_release(
          id: release.fetch("id"),
          title: final_title,
          prerelease: false,
          make_latest: true
        )
      end
      emit(evidence.merge(
        "github_transition" => "complete",
        "final_title" => release["name"],
        "final_prerelease" => release["prerelease"]
      ), options[:output])
    end

    def github_client(optional: false)
      token = @env["SA_GITHUB_TOKEN"] || @env["GH_TOKEN"] || @env["GITHUB_TOKEN"]
      return nil if optional && token.to_s.empty?

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
      allowed = Config::PROJECT_FILES.keys + Config::PLIST_FILES + ["CHANGELOG.md"]
      changed = paths.map { |entry| entry.fetch("path") }
      unexpected = changed - allowed
      raise ValidationError, "release preparation changed unauthorized paths: #{unexpected.join(', ')}" unless unexpected.empty?
      raise ValidationError, "release preparation did not update CHANGELOG.md" unless changed.include?("CHANGELOG.md")
      missing = (Config::PROJECT_FILES.keys + Config::PLIST_FILES) - changed
      raise ValidationError, "release preparation did not update required version files: #{missing.join(', ')}" unless missing.empty?
    end

    def highest_build_from_tags(tags)
      tags.filter_map { |tag| tag[%r{\Aproduction/\d+\.\d+\.\d+-(\d+)\z}, 1]&.to_i }.max || 0
    end

    def release_pull_request_body(naming, release_body)
      <<~BODY
        ## Changes:
        - Prepare #{naming.channel} release #{naming.version} (#{naming.build}).
        - Set the explicit Xcode Cloud-authoritative build number in every versioned project and plist.
        - Regenerate the changelog from the previous release tag.

        ## Closes following issues:
        - Closes: N/A

        ## Tested:
        - Processors:
          - [ ] Intel
          - [ ] Apple Silicon
        - macOS Versions:
          - [ ] 12.x (Monterey)
          - [ ] 13.x (Ventura)
          - [ ] 14.x (Sonoma)
          - [ ] 15.x (Sequoia)
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

    def verify_release_assets!(release, manifest)
      actual_notes_sha = Digest::SHA256.hexdigest(release.fetch("body").to_s)
      unless actual_notes_sha == manifest.fetch("release_notes_sha256")
        raise ValidationError, "GitHub release notes no longer match the archived manifest"
      end

      expected_names = Array(manifest.fetch("artifact_names"))
      assets = Array(release["assets"])
      actual_names = assets.map { |asset| asset["name"] }
      missing = expected_names - actual_names
      raise ValidationError, "GitHub release is missing artifacts: #{missing.join(', ')}" unless missing.empty?
      unexpected = actual_names - expected_names
      raise ValidationError, "GitHub release has unexpected artifacts: #{unexpected.join(', ')}" unless unexpected.empty?

      verification = manifest.fetch("verification", {})
      expected_digests = verification.each_with_object({}) do |(_key, value), result|
        next unless value.is_a?(Hash) && value["zip_path"] && value["zip_sha256"]

        result[File.basename(value["zip_path"])] = value["zip_sha256"]
      end
      missing_digests = expected_names - expected_digests.keys
      unless missing_digests.empty?
        raise ValidationError, "private manifest is missing artifact checksums: #{missing_digests.join(', ')}"
      end
      expected_digests.each do |name, digest|
        unless digest.to_s.match?(/\A[0-9a-f]{64}\z/i)
          raise ValidationError, "private manifest has a malformed checksum for #{name}"
        end
        asset = assets.find { |candidate| candidate["name"] == name }
        actual = asset && asset["digest"].to_s.delete_prefix("sha256:")
        raise ValidationError, "GitHub asset checksum mismatch for #{name}" unless actual == digest
      end
    end

    def help
      <<~HELP
        Sequel Ace release infrastructure #{SequelAceRelease::VERSION}

        Commands:
          guard                      Enforce actor, ref, freeze, confirmation, and enable gates
          plan                       Create a read-only release plan and approval payload
          prepare                    Set explicit version/build values and regenerate CHANGELOG.md
          reconcile-build            Validate Xcode Cloud's authoritative next production build
          verify-artifact            Verify signing, notarization, architecture, metadata, and launch
          verify-artifact-set        Find and verify the distributable app in a Cloud artifact set
          submit                     Stage, validate, and submit a production App Store version
          finalize                   Finalize a GitHub prerelease after App Store release
          github-prepare-pr          Create a verified GitHub App release commit and PR
          github-cleanup-branch      Close and delete an exact failed release branch
          github-wait-checks         Wait for exact-head release PR checks
          github-merge-pr            Recheck and merge the release PR
          github-create-release      Create the tag-backed GitHub prerelease
          github-upload-asset        Upload a verified zip to the prerelease
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
