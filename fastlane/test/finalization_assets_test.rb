# frozen_string_literal: true

require "test_helper"

class FinalizationAssetsTest < Minitest::Test
  def setup
    @cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
    @body = "## App Store Release Notes\n\nA focused update.\n"
    @digest = "a" * 64
  end

  def test_exact_release_body_asset_set_and_archived_checksum_pass
    value = release
    assert @cli.send(:verify_release_assets!, value, manifest, github: public_feed_client(value))
  end

  def test_app_authored_release_requires_exact_anonymous_feed_visibility
    value = release.merge(
      "author" => {
        "login" => SequelAceRelease::ReleasePublisher::RELEASE_APP_LOGIN,
        "id" => SequelAceRelease::ReleasePublisher::RELEASE_APP_BOT_ID,
        "type" => "Bot"
      }
    )
    github = Object.new
    github.define_singleton_method(:public_release_feed_page) { [] }

    error = assert_raises(SequelAceRelease::IntegrityError) do
      @cli.send(:verify_release_assets!, value, manifest, github: github)
    end

    assert_includes error.message, "release feed metadata is malformed"
  end

  def test_unexpected_public_asset_aborts
    value = release
    value["assets"] << value["assets"].first.merge(
      "name" => "unexpected.zip",
      "digest" => "sha256:#{'b' * 64}"
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      @cli.send(:verify_release_assets!, value, manifest, github: public_feed_client(value))
    end
    assert_includes error.message, "unexpected artifacts"
  end

  def test_missing_archived_checksum_aborts
    value = manifest
    value["verification"] = {}

    error = assert_raises(SequelAceRelease::ValidationError) do
      current_release = release
      @cli.send(:verify_release_assets!, current_release, value, github: public_feed_client(current_release))
    end
    assert_includes error.message, "missing artifact checksums"
  end

  def test_duplicate_manifest_checksum_source_aborts
    value = manifest
    value["verification"]["duplicate"] = value["verification"].fetch("production").dup

    error = assert_raises(SequelAceRelease::ValidationError) do
      current_release = release
      @cli.send(:verify_release_assets!, current_release, value, github: public_feed_client(current_release))
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
    github.define_singleton_method(:public_release_feed_page) { [release_data] }
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
    feed_reads = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:public_release_feed_page) do
      feed_reads += 1
      [release_data]
    end
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
      assert_equal 2, feed_reads
    end
  end

  def test_already_finalized_release_is_fully_revalidated_without_replaying_the_mutation
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release.merge("name" => "5.3.2 (20109)", "prerelease" => false)
    reads = Hash.new(0)
    github = Object.new
    github.define_singleton_method(:ref_sha) do |_ref|
      reads[:tag] += 1
      "d" * 40
    end
    github.define_singleton_method(:release_by_tag) do |_tag|
      reads[:release] += 1
      release_data
    end
    github.define_singleton_method(:public_release_feed_page) do
      reads[:feed] += 1
      [release_data]
    end
    github.define_singleton_method(:latest_release) do
      reads[:latest] += 1
      release_data
    end
    github.define_singleton_method(:update_release) { |**_options| raise "replayed an unnecessary mutation" }

    Dir.mktmpdir do |directory|
      output_path = File.join(directory, "finalization.json")

      assert_equal 0, run_finalizer(app_store: app_store, github: github, output_path: output_path)
      evidence = JSON.parse(File.read(output_path))
      assert_equal false, evidence.fetch("transition_required")
      assert_equal "complete", evidence.fetch("github_transition")
    end
    assert_equal({ tag: 2, release: 2, feed: 2, latest: 2 }, reads)
  end

  def test_finalization_aborts_if_the_anonymous_feed_becomes_legacy_incompatible
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    incompatible = release.merge(
      "id" => 99,
      "tag_name" => "production/5.3.1-20104",
      "author" => release.fetch("author").merge("login" => "future-release-bot")
    )
    updates = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:public_release_feed_page) { [release_data, incompatible] }
    github.define_singleton_method(:latest_release) { release_data }
    github.define_singleton_method(:update_release) { |**_options| updates += 1 }

    Dir.mktmpdir do |directory|
      marker = File.join(directory, "terminal-finalization-integrity-failure")

      assert_equal 1, run_finalizer(app_store: app_store, github: github, integrity_marker: marker)
      assert_equal "release asset integrity failure\n", File.read(marker)
    end
    assert_equal 0, updates
  end

  def test_finalization_keeps_anonymous_feed_transport_failures_retryable
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    updates = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:public_release_feed_page) do
      raise SequelAceRelease::APIError, "GitHub release feed failed with HTTP 403"
    end
    github.define_singleton_method(:latest_release) { release_data }
    github.define_singleton_method(:update_release) { |**_options| updates += 1 }

    Dir.mktmpdir do |directory|
      marker = File.join(directory, "terminal-finalization-integrity-failure")

      assert_equal 1, run_finalizer(app_store: app_store, github: github, integrity_marker: marker)
      refute_path_exists marker
    end
    assert_equal 0, updates
  end

  def test_finalization_leaves_a_post_transition_feed_transport_failure_retryable
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    updates = 0
    feed_reads = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:public_release_feed_page) do
      feed_reads += 1
      raise SequelAceRelease::APIError, "GitHub release feed failed with HTTP 503" if feed_reads == 2

      [release_data]
    end
    github.define_singleton_method(:latest_release) { release_data }
    github.define_singleton_method(:update_release) do |**options|
      updates += 1
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end

    Dir.mktmpdir do |directory|
      marker = File.join(directory, "terminal-finalization-integrity-failure")
      output = File.join(directory, "finalization.json")

      assert_equal 1, run_finalizer(
        app_store: app_store,
        github: github,
        integrity_marker: marker,
        output_path: output
      )
      refute_path_exists marker
      refute_path_exists output
    end
    assert_equal 1, updates
    assert_equal 2, feed_reads
  end

  def test_finalization_leaves_every_authenticated_post_transition_readback_retryable
    %i[tag release latest].each do |failure_point|
      live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
      app_store = Object.new
      app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
      app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
      release_data = release
      calls = Hash.new(0)
      updates = 0
      github = Object.new
      github.define_singleton_method(:ref_sha) do |_ref|
        calls[:tag] += 1
        raise SequelAceRelease::APIError, "GitHub tag readback failed with HTTP 503" if failure_point == :tag && calls[:tag] == 2

        "d" * 40
      end
      github.define_singleton_method(:release_by_tag) do |_tag|
        calls[:release] += 1
        if failure_point == :release && calls[:release] == 2
          raise SequelAceRelease::APIError, "GitHub release readback failed with HTTP 503"
        end

        release_data
      end
      github.define_singleton_method(:public_release_feed_page) { [release_data] }
      github.define_singleton_method(:latest_release) do
        calls[:latest] += 1
        if failure_point == :latest && calls[:latest] == 2
          raise SequelAceRelease::APIError, "GitHub latest readback failed with HTTP 503"
        end

        release_data
      end
      github.define_singleton_method(:update_release) do |**options|
        updates += 1
        release_data = release_data.merge(
          "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
        )
      end

      Dir.mktmpdir do |directory|
        marker = File.join(directory, "terminal-finalization-integrity-failure")
        output = File.join(directory, "finalization.json")

        assert_equal 1, run_finalizer(
          app_store: app_store,
          github: github,
          integrity_marker: marker,
          output_path: output
        ), failure_point
        refute_path_exists marker, failure_point
        refute_path_exists output, failure_point
      end
      assert_equal 1, updates, failure_point
    end
  end

  def test_finalization_keeps_a_post_transition_incompatible_feed_terminal
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    release_data = release
    incompatible = release.merge(
      "id" => 99,
      "tag_name" => "production/5.3.1-20104",
      "author" => release.fetch("author").merge("login" => "future-release-bot")
    )
    updates = 0
    feed_reads = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:public_release_feed_page) do
      feed_reads += 1
      feed_reads == 1 ? [release_data] : [release_data, incompatible]
    end
    github.define_singleton_method(:latest_release) { release_data }
    github.define_singleton_method(:update_release) do |**options|
      updates += 1
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end

    Dir.mktmpdir do |directory|
      marker = File.join(directory, "terminal-finalization-integrity-failure")

      assert_equal 1, run_finalizer(app_store: app_store, github: github, integrity_marker: marker)
      assert_equal "release asset integrity failure\n", File.read(marker)
    end
    assert_equal 1, updates
    assert_equal 2, feed_reads
  end

  def test_finalization_rejects_a_stale_anonymous_prerelease_after_transition
    live_snapshot = metadata_snapshot(build: 20_109, state: "READY_FOR_DISTRIBUTION", phased_state: "ACTIVE")
    app_store = Object.new
    app_store.define_singleton_method(:metadata_snapshot) { |**_options| live_snapshot }
    app_store.define_singleton_method(:latest_released_version) { |**_options| live_snapshot.fetch("version") }
    stale_prerelease = release
    release_data = stale_prerelease
    updates = 0
    feed_reads = 0
    github = Object.new
    github.define_singleton_method(:ref_sha) { |_ref| "d" * 40 }
    github.define_singleton_method(:release_by_tag) { |_tag| release_data }
    github.define_singleton_method(:public_release_feed_page) do
      feed_reads += 1
      [stale_prerelease]
    end
    github.define_singleton_method(:latest_release) { release_data }
    github.define_singleton_method(:update_release) do |**options|
      updates += 1
      release_data = release_data.merge(
        "name" => options.fetch(:title), "draft" => false, "prerelease" => options.fetch(:prerelease)
      )
    end

    Dir.mktmpdir do |directory|
      marker = File.join(directory, "terminal-finalization-integrity-failure")

      assert_equal 1, run_finalizer(app_store: app_store, github: github, integrity_marker: marker)
      assert_equal "release asset integrity failure\n", File.read(marker)
    end
    assert_equal 1, updates
    assert_equal 2, feed_reads
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
        raise SequelAceRelease::APIError.new("GitHub API returned HTTP 404", status: 404)
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

  def run_finalizer(app_store:, github:, integrity_marker: nil, output_path: nil)
    unless github.respond_to?(:public_release_feed_page)
      github.define_singleton_method(:public_release_feed_page) do
        [github.release_by_tag("production/5.3.2-20109")]
      end
    end
    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, "manifest.json")
      release_manifest.write(manifest_path)
      cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
      cli.stub(:app_store_client, app_store) do
        cli.stub(:github_client, github) do
          arguments = [
            "finalize",
            "--manifest", manifest_path,
            "--confirm", "FINALIZE production/5.3.2-20109"
          ]
          arguments.concat(["--integrity-failure-marker", integrity_marker]) if integrity_marker
          arguments.concat(["--output", output_path]) if output_path
          cli.run(arguments)
        end
      end
    end
  end

  def public_feed_client(value)
    Object.new.tap do |client|
      client.define_singleton_method(:public_release_feed_page) { [value] }
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
