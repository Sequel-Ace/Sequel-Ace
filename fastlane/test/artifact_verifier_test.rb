# frozen_string_literal: true

require "test_helper"

class ArtifactVerifierTest < Minitest::Test
  class FakeArtifactRunner
    def initialize(team: SequelAceRelease::Config::TEAM_ID, architectures: "arm64 x86_64", fail_stapler: false, executable: "Sequel Ace")
      @team = team
      @architectures = architectures
      @fail_stapler = fail_stapler
      @executable = executable
    end

    def run(*command, **_options)
      stdout = ""
      stderr = ""
      case command.first
      when "/usr/bin/plutil"
        key = command[2]
        stdout = {
          "CFBundleIdentifier" => "com.sequel-ace.sequel-ace",
          "CFBundleShortVersionString" => "5.3.2",
          "CFBundleVersion" => "20105",
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
    attr_reader :commands

    def initialize(
      pgrep_results: [[false, ""], [true, "4242\n"]],
      process_command: Pathname.new("/bin/echo").realpath.to_s,
      kill_zero_results: [[false, ""]]
    )
      @commands = []
      @pgrep_results = pgrep_results
      @process_command = process_command
      @kill_zero_results = kill_zero_results
    end

    def run(*command, **_options)
      @commands << command
      success, stdout = if command.first == "/usr/bin/pgrep"
                          @pgrep_results.shift
                        elsif command.first == "/bin/ps"
                          [true, "#{@process_command}\n"]
                        elsif command.first == "/bin/kill" && command[1] == "-0"
                          @kill_zero_results.shift
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
      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::ArtifactVerifier.new(
          runner: FakeArtifactRunner.new(executable: "../Unrelated")
        ).verify(path: app, version: "5.3.2", build: 20_105, channel: "production", launch: true)
      end
      assert_includes error.message, "executable name"
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
    assert_includes runner.commands, ["/bin/ps", "-p", "4242", "-o", "command="]
    assert_includes runner.commands, ["/bin/kill", "-0", "4242"]
    refute runner.commands.any? { |command| command.first == "/usr/bin/pkill" }
    refute runner.commands.any? { |command| command.first == "/usr/bin/osascript" }
  end

  def test_launch_refuses_to_terminate_when_more_than_one_process_matches
    runner = LaunchRunner.new(pgrep_results: [[false, ""], [true, "4242\n4243\n"]])
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

    assert_includes error.message, "exactly one"
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

  def with_app
    Dir.mktmpdir do |directory|
      app = Pathname.new(directory).join("Sequel Ace.app")
      FileUtils.mkdir_p(app.join("Contents/MacOS"))
      app.join("Contents/Info.plist").write("fixture")
      app.join("Contents/MacOS/Sequel Ace").write("fixture")
      yield app
    end
  end
end
