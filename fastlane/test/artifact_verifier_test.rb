# frozen_string_literal: true

require "test_helper"

class ArtifactVerifierTest < Minitest::Test
  class FakeArtifactRunner
    def initialize(team: SequelAceRelease::Config::TEAM_ID, architectures: "arm64 x86_64", fail_stapler: false)
      @team = team
      @architectures = architectures
      @fail_stapler = fail_stapler
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
          "CFBundleExecutable" => "Sequel Ace"
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

    def initialize
      @commands = []
      @pgrep_results = [false, true, false]
    end

    def run(*command, **_options)
      @commands << command
      success = command.first == "/usr/bin/pgrep" ? @pgrep_results.shift : true
      SequelAceRelease::CommandRunner::Result.new(
        stdout: "",
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

  def test_launch_passes_the_process_name_as_data_instead_of_script_source
    runner = LaunchRunner.new
    verifier = SequelAceRelease::ArtifactVerifier.new(runner: runner)
    process_name = 'Sequel Ace\\"; Application("Finder").quit(); //'

    verifier.stub(:sleep, nil) do
      verifier.send(:launch_and_quit, Pathname.new("/tmp/Sequel Ace.app"), process_name)
    end

    osascript = runner.commands.find { |command| command.first == "/usr/bin/osascript" }
    assert_equal(
      [
        "/usr/bin/osascript",
        "-l", "JavaScript",
        "-e", "function run(argv) { Application(argv[0]).quit(); }",
        process_name
      ],
      osascript
    )
    refute_includes osascript.fetch(4), process_name
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
