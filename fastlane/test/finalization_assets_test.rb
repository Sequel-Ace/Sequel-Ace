# frozen_string_literal: true

require "test_helper"

class FinalizationAssetsTest < Minitest::Test
  def setup
    @cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    @body = "## App Store Release Notes\n\nA focused update.\n"
    @digest = "a" * 64
  end

  def test_exact_release_body_asset_set_and_archived_checksum_pass
    assert @cli.send(:verify_release_assets!, release, manifest)
  end

  def test_unexpected_public_asset_aborts
    value = release
    value["assets"] << value["assets"].first.merge(
      "name" => "unexpected.zip",
      "digest" => "sha256:#{'b' * 64}"
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      @cli.send(:verify_release_assets!, value, manifest)
    end
    assert_includes error.message, "unexpected artifacts"
  end

  def test_missing_archived_checksum_aborts
    value = manifest
    value["verification"] = {}

    error = assert_raises(SequelAceRelease::ValidationError) do
      @cli.send(:verify_release_assets!, release, value)
    end
    assert_includes error.message, "missing artifact checksums"
  end

  def test_duplicate_manifest_checksum_source_aborts
    value = manifest
    value["verification"]["duplicate"] = value["verification"].fetch("production").dup

    error = assert_raises(SequelAceRelease::ValidationError) do
      @cli.send(:verify_release_assets!, release, value)
    end
    assert_includes error.message, "duplicate artifact checksums"
  end

  def test_validate_only_does_not_make_the_public_github_transition
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) do |app_id:, version:|
      raise "wrong app" unless app_id == SequelAceRelease::Config::PRODUCTION_APP_ID
      raise "wrong version" unless version == "5.3.2"

      live_snapshot
    end
    app_store.define_singleton_method(:latest_released_version) do |app_id:|
      raise "wrong app" unless app_id == SequelAceRelease::Config::PRODUCTION_APP_ID

      live_snapshot.fetch("version")
    end
    release_data = release
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:latest_release) { { "id" => 99, "tag_name" => "production/5.3.1-20104" } }
    github.define_singleton_method(:update_release) { |**_options| raise "validate-only mutated GitHub" }

    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      output_path = File.join(directory, "finalization-validation.json")
      release_manifest.write(manifest_path)
      status = @cli.stub(:app_store_client, app_store) do
        @cli.stub(:github_client, github) do
          @cli.run([
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20109",
            "--validate-only",
            "--output", output_path
          ])
        end
      end

      assert_equal 0, status
      evidence = JSON.parse(File.read(output_path))
      assert_equal "durably_validated_before_public_transition", evidence.fetch("github_transition")
      assert_equal true, evidence.fetch("transition_required")
      assert_equal "5.3.2 (20109)", evidence.fetch("target_title")
      assert_equal "d" * 40, evidence.fetch("release_commit_sha")
    end
  end

  def test_finalization_clears_prerelease_and_marks_release_latest
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    update_options = nil
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:latest_release) { release_data }
    github.define_singleton_method(:update_release) do |**options|
      update_options = options
      release_data = release_data.merge(
        "name" => options.fetch(:title),
        "draft" => false,
        "prerelease" => options.fetch(:prerelease)
      )
    end

    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      release_manifest.write(manifest_path)
      status = @cli.stub(:app_store_client, app_store) do
        @cli.stub(:github_client, github) do
          @cli.run([
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20109"
          ])
        end
      end

      assert_equal 0, status
      assert_equal(
        {
          id: 100,
          tag: "production/5.3.2-20109",
          target_sha: "d" * 40,
          title: "5.3.2 (20109)",
          prerelease: false,
          make_latest: true
        },
        update_options
      )
    end
  end

  def test_finalization_rechecks_the_tag_after_the_public_transition
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    events = []
    github = Object.new
    github.define_singleton_method(:ref_sha) do |ref|
      events << [:ref_sha, ref]
      events.count { |event| event.first == :ref_sha } == 1 ? "d" * 40 : "e" * 40
    end
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:latest_release) { { "id" => 99, "tag_name" => "production/5.3.1-20104" } }
    github.define_singleton_method(:update_release) do |**options|
      events << [:update_release, options]
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end

    assert_equal 1, run_finalizer(app_store: app_store, github: github)
    assert_equal(
      [
        [:ref_sha, "tags/production/5.3.2-20109"],
        [:update_release, {
          id: 100,
          tag: "production/5.3.2-20109",
          target_sha: "d" * 40,
          title: "5.3.2 (20109)",
          prerelease: false,
          make_latest: true
        }],
        [:ref_sha, "tags/production/5.3.2-20109"]
      ],
      events
    )
  end

  def test_finalization_rejects_a_tag_moved_after_archival
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "e" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| raise "moved tag reached release mutation path" }

    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      release_manifest.write(manifest_path)
      error = StringIO.new
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: error, env: {})
      status = cli.stub(:app_store_client, app_store) do
        cli.stub(:github_client, github) do
          cli.run([
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20109",
            "--validate-only"
          ])
        end
      end

      assert_equal 1, status
      assert_includes error.string, "release tag moved after archival"
    end
  end

  def test_finalization_rejects_an_older_live_app_store_version
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) do |**_options|
      {
        "id" => "newer-version-id",
        "attributes" => { "versionString" => "5.3.3", "appVersionState" => "READY_FOR_DISTRIBUTION" }
      }
    end
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| raise "stale version reached GitHub" }

    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      release_manifest.write(manifest_path)
      error = StringIO.new
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: error, env: {})
      status = cli.stub(:app_store_client, app_store) do
        cli.stub(:github_client, github) do
          cli.run([
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20109",
            "--validate-only"
          ])
        end
      end

      assert_equal 1, status
      assert_includes error.string, "not the latest released"
    end
  end

  def test_finalization_reasserts_latest_for_an_already_final_looking_release
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release.merge("name" => "5.3.2 (20109)", "prerelease" => false)
    updates = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:latest_release) do
      updates.zero? ? { "id" => 99, "tag_name" => "production/5.3.1-20104" } : release_data
    end
    github.define_singleton_method(:update_release) do |**options|
      updates += 1
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end

    status = run_finalizer(app_store: app_store, github: github)

    assert_equal 0, status
    assert_equal 1, updates
  end

  def test_finalization_treats_a_missing_current_latest_release_as_not_latest
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    updates = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:latest_release) do
      if updates.zero?
        raise SequelAceRelease::APIError, "GitHub API returned HTTP 404"
      end

      release_data
    end
    github.define_singleton_method(:update_release) do |**options|
      updates += 1
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end

    status = run_finalizer(app_store: app_store, github: github)

    assert_equal 0, status
    assert_equal 1, updates
  end

  def test_finalization_rejects_a_draft_or_unauthorized_publisher
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }

    candidates = [
      release.merge("draft" => true),
      release.merge("author" => { "login" => "Kaspik" }),
      release.merge("author" => {
        "login" => SequelAceRelease::ReleasePublisher::USER_LOGIN,
        "id" => SequelAceRelease::ReleasePublisher::USER_ID + 1
      })
    ]
    candidates.each do |candidate|
      github = Object.new
      github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
      github.define_singleton_method(:release_by_tag) { |_tag| candidate }

      assert_equal 1, run_finalizer(app_store: app_store, github: github)
    end
  end

  def test_finalization_fails_if_latest_readback_does_not_match
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    latest_reads = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:update_release) do |**options|
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end
    github.define_singleton_method(:latest_release) do
      latest_reads += 1
      { "id" => 99, "tag_name" => "production/5.3.1-20104", "name" => "5.3.1", "draft" => false, "prerelease" => false }
    end

    assert_equal 1, run_finalizer(app_store: app_store, github: github)
    assert_equal 2, latest_reads
  end

  private

  def release
    github_release_payload(
      tag: "production/5.3.2-20109",
      title: "5.3.2 (20109) - Release Candidate 1",
      body: @body,
      assets: [github_release_asset(
        name: "Sequel-Ace-5.3.2.zip",
        digest: @digest
      )]
    )
  end

  def run_finalizer(app_store:, github:)
    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      release_manifest.write(manifest_path)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      cli.stub(:app_store_client, app_store) do
        cli.stub(:github_client, github) do
          cli.run([
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20109"
          ])
        end
      end
    end
  end

  def release_manifest
    naming = SequelAceRelease::ReleaseNaming.new(
      channel: "production", version: "5.3.2", build: 20_109, iteration: 1
    )
    SequelAceRelease::Manifest.create(
      approval: approval(release_notes_sha256: Digest::SHA256.hexdigest(@body)),
      naming: naming,
      base_sha: "b" * 40,
      canonical_build: 20_109,
      production_build_evidence: production_build_evidence(target: 20_109),
      release_notes_sha256: Digest::SHA256.hexdigest(@body),
      state: "submitted"
    ).with(
      "release_commit_sha" => "d" * 40,
      "verification" => manifest.fetch("verification")
    )
  end

  def manifest
    {
      "release_notes_sha256" => Digest::SHA256.hexdigest(@body),
      "artifact_names" => ["Sequel-Ace-5.3.2.zip"],
      "verification" => {
        "production" => {
          "zip_path" => "/runner/artifacts/Sequel-Ace-5.3.2.zip",
          "zip_sha256" => @digest
        }
      }
    }
  end
end
