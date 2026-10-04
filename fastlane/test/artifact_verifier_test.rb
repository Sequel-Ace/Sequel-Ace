# frozen_string_literal: true

require "test_helper"

class ArtifactVerifierTest < Minitest::Test
  class FakeArtifactRunner
    attr_reader :commands

    def initialize(
      team: SequelAceRelease::Config::TEAM_ID,
      architectures: "arm64 x86_64",
      fail_stapler: false,
      executable: "Sequel Ace",
      release_tag: "production/5.3.2-20105"
    )
      @commands = []
      @team = team
      @architectures = architectures
      @fail_stapler = fail_stapler
      @executable = executable
      @release_tag = release_tag
    end

    def run(*command, **_options)
      @commands << command
      stdout = ""
      stderr = ""
      case command.first
      when "/usr/bin/plutil"
        key = command[2]
        stdout = {
          "CFBundleIdentifier" => "com.sequel-ace.sequel-ace",
          "CFBundleShortVersionString" => "5.3.2",
          "CFBundleVersion" => "20105",
          SequelAceRelease::Config::RELEASE_TAG_PLIST_KEY => @release_tag,
          "CFBundleExecutable" => @executable
        }.fetch(key)
      when "/usr/bin/lipo"
        stdout = @architectures
      when "/usr/bin/codesign"
        if command.include?("-d")
          stderr = "Authority=Developer ID Application: Moballo, LLC (NKQ4HJ66PX)\nTeamIdentifier=#{@team}\n"
        end
      when "/usr/bin/xcrun"
        raise SequelAceRelease::CommandError, "stapled ticket is invalid" if @fail_stapler
      end
      SequelAceRelease::CommandRunner::Result.new(
        stdout: stdout,
        stderr: stderr,
        status: FakeStatus.new(true)
      )
    end
  end

  class LaunchRunner
    attr_reader :commands, :options, :spawn_commands, :spawn_options

    def initialize(
      pgrep_results: [[false, ""]],
      process_command: Pathname.new("/bin/echo").realpath.to_s,
      process_commands: nil,
      kill_zero_results: [[false, ""]],
      spawn_pid: 4242,
      signature_text: "Authority=Developer ID Application: Moballo, LLC (NKQ4HJ66PX)\nTeamIdentifier=#{SequelAceRelease::Config::TEAM_ID}\n"
    )
      @commands = []
      @options = []
      @spawn_commands = []
      @spawn_options = []
      @pgrep_results = pgrep_results
      @process_commands = Array(process_commands || process_command)
      @kill_zero_results = kill_zero_results
      @spawn_pid = spawn_pid
      @signature_text = signature_text
    end

    def spawn(*command, **options)
      @spawn_commands << command
      @spawn_options << options
      @spawn_pid
    end

    def run(*command, **options)
      @commands << command
      @options << options
      success, stdout = if command.first == "/usr/bin/pgrep"
                          @pgrep_results.shift
                        elsif command.first == "/bin/ps"
                          process_command = @process_commands.length > 1 ? @process_commands.shift : @process_commands.first
                          [true, "#{process_command}\n"]
                        elsif command.first == "/bin/kill" && command[1] == "-0"
                          @kill_zero_results.shift
                        elsif command.first == "/usr/bin/codesign" && command.include?("-d")
                          [true, @signature_text]
                        else
                          [true, ""]
                        end
      SequelAceRelease::CommandRunner::Result.new(
        stdout: stdout,
        stderr: "",
        status: FakeStatus.new(success)
      )
    end
  end

  FakeStatus = Struct.new(:success?)

  def test_verifies_expected_artifact_contract
    with_app do |app|
      result = SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new).verify(
        path: app,
        version: "5.3.2",
        build: 20_105,
        channel: "production"
      )
      assert_equal %w[arm64 x86_64], result.fetch("architectures")
      assert_equal SequelAceRelease::Config::TEAM_ID, result.fetch("team_id")
    end
  end

  def test_verifies_embedded_canonical_release_tag
    with_app do |app|
      result = SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new).verify(
        path: app,
        version: "5.3.2",
        build: 20_105,
        channel: "production",
        release_tag: "production/5.3.2-20105"
      )
      assert_equal "production/5.3.2-20105", result.fetch("release_tag")

      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new).verify(
          path: app,
          version: "5.3.2",
          build: 20_105,
          channel: "production",
          release_tag: "beta/5.3.2-20105"
        )
      end
      assert_includes error.message, "release tag"
    end
  end

  def test_wrong_team_and_missing_architecture_abort
    with_app do |app|
      assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new(team: "WRONGTEAM")).verify(
          path: app, version: "5.3.2", build: 20_105, channel: "production"
        )
      end
      assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new(architectures: "arm64")).verify(
          path: app, version: "5.3.2", build: 20_105, channel: "production"
        )
      end
    end
  end

  def test_wrong_build_notarization_and_checksum_abort
    with_app do |app|
      assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new).verify(
          path: app, version: "5.3.2", build: 20_106, channel: "production"
        )
      end
      assert_raises(SequelAceRelease::CommandError) do
        SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new(fail_stapler: true)).verify(
          path: app, version: "5.3.2", build: 20_105, channel: "production"
        )
      end
      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: FakeArtifactRunner.new).verify(
          path: app,
          version: "5.3.2",
          build: 20_105,
          channel: "production",
          expected_sha256: "0" * 64
        )
      end
      assert_includes error.message, "checksum"
    end
  end

  def test_malformed_executable_name_aborts_before_launch_or_process_lookup
    with_app do |app|
      runner = FakeArtifactRunner.new(executable: "../Unrelated")
      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(
          runner: runner
        ).verify(path: app, version: "5.3.2", build: 20_105, channel: "production", launch: true)
      end
      assert_includes error.message, "executable name"
      refute runner.commands.any? { |command| %w[/usr/bin/open /usr/bin/pgrep /bin/ps /bin/kill].include?(command.first) }
    end
  end

  def test_executable_symlink_outside_the_bundle_aborts_before_process_control
    with_app do |app|
      executable = app.join("Contents/MacOS/Sequel Ace")
      outside_executable = app.parent.join("outside-executable")
      outside_executable.write("fixture")
      executable.delete
      File.symlink(outside_executable, executable)
      runner = FakeArtifactRunner.new

      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: runner).verify(
          path: app,
          version: "5.3.2",
          build: 20_105,
          channel: "production",
          launch: true
        )
      end

      assert_includes error.message, "symbolic link"
      refute runner.commands.any? { |command| %w[/usr/bin/lipo /usr/bin/open /usr/bin/pgrep /bin/ps /bin/kill].include?(command.first) }
    end
  end

  def test_symlinked_executable_directory_outside_the_bundle_is_rejected
    Dir.mktmpdir do |directory|
      app = Pathname.new(directory).join("Sequel Ace.app")
      FileUtils.mkdir_p(app.join("Contents"))
      app.join("Contents/Info.plist").write("fixture")
      outside_directory = Pathname.new(directory).join("outside-macos")
      FileUtils.mkdir_p(outside_directory)
      outside_directory.join("Sequel Ace").write("fixture")
      File.symlink(outside_directory, app.join("Contents/MacOS"))
      runner = FakeArtifactRunner.new

      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(runner: runner).verify(
          path: app,
          version: "5.3.2",
          build: 20_105,
          channel: "production"
        )
      end

      assert_includes error.message, "outside Contents/MacOS"
      refute runner.commands.any? { |command| command.first == "/usr/bin/lipo" }
    end
  end

  def test_launch_terminates_the_exact_observed_process_without_apple_events
    runner = LaunchRunner.new
    verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)
    executable = Pathname.new("/bin/echo")

    verifier.stub(:sleep, nil) do
      verifier.send(:launch_and_quit, Pathname.new("/tmp/Sequel Ace.app"), executable)
    end

    assert_includes runner.commands, ["/bin/kill", "-TERM", "4242"]
    assert_includes runner.commands, ["/usr/bin/pgrep", "-x", "echo"]
    assert_includes runner.commands, ["/bin/ps", "-ww", "-p", "4242", "-o", "command="]
    assert_includes runner.commands, ["/bin/kill", "-0", "4242"]
    assert_includes runner.spawn_commands, [Pathname.new("/bin/echo")]
    assert_equal Pathname.new("/tmp"), runner.spawn_options.first.fetch(:chdir)
    refute runner.commands.any? { |command| command.first == "/usr/bin/open" }
    refute runner.commands.any? { |command| command.first == "/usr/bin/pkill" }
    refute runner.commands.any? { |command| command.first == "/usr/bin/osascript" }
  end

  def test_launch_accepts_a_matching_signed_app_translocation
    with_app do |app|
      with_translocated_copy(app) do |translocated_executable|
        runner = LaunchRunner.new(process_command: translocated_executable.realpath.to_s)
        verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

        verifier.stub(:sleep, nil) do
          verifier.send(:launch_and_quit, app, app.join("Contents/MacOS/Sequel Ace"))
        end

        assert_includes runner.commands, ["/bin/kill", "-TERM", "4242"]
        assert runner.commands.any? { |command|
          command[0, 5] == ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2"]
        }
      end
    end
  end

  def test_launch_rejects_an_app_translocation_with_a_different_executable
    with_app do |app|
      with_translocated_copy(app, contents: "different fixture") do |translocated_executable|
        runner = LaunchRunner.new(process_command: translocated_executable.realpath.to_s)
        verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

        error = assert_raises(SequelAceRelease::ValidationError) do
          verifier.stub(:sleep, nil) do
            verifier.send(:launch_and_quit, app, app.join("Contents/MacOS/Sequel Ace"))
          end
        end

        assert_includes error.message, "does not belong"
        refute runner.commands.any? { |command| command.first == "/bin/kill" }
      end
    end
  end

  def test_launch_rejects_an_app_translocation_signed_by_another_team
    signature = "Authority=Developer ID Application: Moballo, LLC (NKQ4HJ66PX)\nTeamIdentifier=WRONGTEAM\n"

    assert_rejects_translocated_signature(signature, "TeamIdentifier WRONGTEAM")
  end

  def test_launch_rejects_an_app_translocation_without_a_moballo_developer_id_authority
    signature = "Authority=Apple Root CA\nTeamIdentifier=#{SequelAceRelease::Config::TEAM_ID}\n"

    assert_rejects_translocated_signature(signature, "Moballo Developer ID Application")
  end

  def test_launch_revalidates_a_translocated_process_before_signaling
    with_app do |app|
      with_translocated_copy(app) do |translocated_executable|
        runner = LaunchRunner.new(
          process_commands: [
            translocated_executable.realpath.to_s,
            "/Applications/Unrelated.app/Contents/MacOS/Sequel Ace"
          ]
        )
        verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

        error = assert_raises(SequelAceRelease::ValidationError) do
          verifier.stub(:sleep, nil) do
            verifier.send(:launch_and_quit, app, app.join("Contents/MacOS/Sequel Ace"))
          end
        end

        assert_includes error.message, "identity changed before graceful termination"
        assert_equal 2, runner.commands.count { |command| command.first == "/bin/ps" }
        refute runner.commands.any? { |command| command.first == "/bin/kill" }
      end
    end
  end

  def test_launch_force_terminates_the_verified_pid_after_the_graceful_timeout
    runner = LaunchRunner.new(kill_zero_results: [[true, ""], [false, ""]])
    verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)
    times = [Time.at(0), Time.at(20), Time.at(20)]

    error = assert_raises(SequelAceRelease::ValidationError) do
      Time.stub(:now, -> { times.shift || Time.at(25) }) do
        verifier.stub(:sleep, nil) do
          verifier.send(
            :launch_and_quit,
            Pathname.new("/tmp/Sequel Ace.app"),
            Pathname.new("/bin/echo")
          )
        end
      end
    end

    assert_includes error.message, "did not quit cleanly"
    assert_includes runner.commands, ["/bin/kill", "-TERM", "4242"]
    assert_includes runner.commands, ["/bin/kill", "-KILL", "4242"]
    assert_equal 3, runner.commands.count { |command| command.first == "/bin/ps" }
    final_identity_check = runner.commands.rindex(["/bin/ps", "-ww", "-p", "4242", "-o", "command="])
    forced_termination = runner.commands.index(["/bin/kill", "-KILL", "4242"])
    assert_operator final_identity_check, :<, forced_termination
    assert_equal 2, runner.commands.count { |command| command[0, 2] == ["/bin/kill", "-0"] }
  end

  def test_launch_refuses_to_start_when_the_executable_is_already_running
    runner = LaunchRunner.new(pgrep_results: [[true, "4242\n"]])
    verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

    error = assert_raises(SequelAceRelease::ValidationError) do
      verifier.stub(:sleep, nil) do
        verifier.send(
          :launch_and_quit,
          Pathname.new("/tmp/Sequel Ace.app"),
          Pathname.new("/bin/echo")
        )
      end
    end

    assert_includes error.message, "already running"
    assert_empty runner.spawn_commands
    refute runner.commands.any? { |command| command.first == "/bin/kill" }
  end

  def test_launch_rejects_an_invalid_spawned_process_identifier
    runner = LaunchRunner.new(spawn_pid: 0)
    verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

    error = assert_raises(SequelAceRelease::ValidationError) do
      verifier.stub(:sleep, nil) do
        verifier.send(
          :launch_and_quit,
          Pathname.new("/tmp/Sequel Ace.app"),
          Pathname.new("/bin/echo")
        )
      end
    end

    assert_includes error.message, "invalid process identifier"
    refute runner.commands.any? { |command| command.first == "/bin/kill" }
  end

  def test_launch_refuses_to_signal_a_pid_from_another_executable
    runner = LaunchRunner.new(process_command: "/Applications/Unrelated.app/Contents/MacOS/echo")
    verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

    error = assert_raises(SequelAceRelease::ValidationError) do
      verifier.stub(:sleep, nil) do
        verifier.send(
          :launch_and_quit,
          Pathname.new("/tmp/Sequel Ace.app"),
          Pathname.new("/bin/echo")
        )
      end
    end

    assert_includes error.message, "does not belong"
    refute runner.commands.any? { |command| command.first == "/bin/kill" }
  end

  def test_directory_digest_has_unambiguous_path_and_content_boundaries
    verifier = SequelAceRelease::ArtifactVerifier.new
    Dir.mktmpdir do |first_directory|
      Dir.mktmpdir do |second_directory|
        File.write(File.join(first_directory, "a"), "bc")
        File.write(File.join(second_directory, "ab"), "c")

        refute_equal(
          verifier.send(:sha256, Pathname.new(first_directory)),
          verifier.send(:sha256, Pathname.new(second_directory))
        )
      end
    end
  end

  private

  def assert_rejects_translocated_signature(signature, expected_error)
    with_app do |app|
      with_translocated_copy(app) do |translocated_executable|
        runner = LaunchRunner.new(
          process_command: translocated_executable.realpath.to_s,
          signature_text: signature
        )
        verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)

        error = assert_raises(SequelAceRelease::ValidationError) do
          verifier.stub(:sleep, nil) do
            verifier.send(:launch_and_quit, app, app.join("Contents/MacOS/Sequel Ace"))
          end
        end

        assert_includes error.message, expected_error
        refute runner.commands.any? { |command| command.first == "/bin/kill" }
      end
    end
  end

  def with_app
    Dir.mktmpdir do |directory|
      app = Pathname.new(directory).join("Sequel Ace.app")
      FileUtils.mkdir_p(app.join("Contents/MacOS"))
      app.join("Contents/Info.plist").write("fixture")
      app.join("Contents/MacOS/Sequel Ace").write("fixture")
      yield app
    end
  end

  def with_translocated_copy(app, contents: nil)
    uuid = "01234567-89AB-CDEF-0123-456789ABCDEF"
    root = Pathname.new(Dir.tmpdir).join("AppTranslocation", uuid)
    executable = root.join("d", app.basename, "Contents/MacOS/Sequel Ace")
    FileUtils.mkdir_p(executable.dirname)
    executable.binwrite(contents || app.join("Contents/MacOS/Sequel Ace").binread)
    yield executable
  ensure
    FileUtils.rm_rf(root) if root
  end
end
