# frozen_string_literal: true

require "test_helper"

class CommandRunnerTest < Minitest::Test
  def test_can_spawn_a_long_running_gui_process_without_waiting
    process_id = nil
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Dir.mktmpdir do |directory|
      executable = File.join(directory, "long running ; child")
      File.write(executable, "#!#{RbConfig.ruby}\nsleep 10\n")
      File.chmod(0o700, executable)

      begin
        process_id = SequelAceRelease::CommandRunner.new.spawn(executable)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

        assert_operator process_id, :>, 0
        assert_operator elapsed, :<, 2
        assert Process.kill(0, process_id)
      ensure
        begin
          Process.kill("TERM", process_id) if process_id
        rescue Errno::ESRCH
          # The child already exited and was reaped by the detached waiter.
        end
      end
    end
  end

  def test_spawn_requires_a_command
    assert_raises(ArgumentError) { SequelAceRelease::CommandRunner.new.spawn }
  end

  def test_spawn_wraps_system_call_failures_without_exposing_the_command
    Dir.mktmpdir do |directory|
      missing_command = File.join(directory, "missing-spawn-command-secret-value")

      error = assert_raises(SequelAceRelease::CommandError) do
        SequelAceRelease::CommandRunner.new.spawn(missing_command)
      end

      assert_includes error.message, "Errno::ENOENT"
      assert_includes error.message, "errno"
      refute_includes error.message, missing_command
      refute_includes error.message, "secret-value"
    end
  end

  def test_can_run_a_gui_launcher_without_capture_pipes
    child_pid = nil
    pid_path = nil
    result = nil
    runner_thread = nil

    Dir.mktmpdir do |directory|
      begin
        pid_path = File.join(directory, "inherited-stream-child.pid")
        # Publish the pid by rename, which is atomic within a directory, so the
        # path never exists holding a partial write. Writing in place let the
        # reader below observe an empty file and fail parsing it.
        launcher = <<~'RUBY'
          child_pid = fork do
            $stdout.write("inherited output")
            $stderr.write("inherited error")
            sleep 5
          end
          pid_path = ARGV.fetch(0)
          staging_path = "#{pid_path}.partial"
          File.write(staging_path, child_pid)
          File.rename(staging_path, pid_path)
        RUBY

        runner_thread = Thread.new do
          SequelAceRelease::CommandRunner.new.run(
            RbConfig.ruby,
            "-e",
            launcher,
            pid_path,
            discard_output: true
          )
        end
        runner_thread.report_on_exception = false
        # Wait for content that parses, not merely for the path to appear: the
        # pid is what the rest of the test needs, and this stays correct even
        # if the launcher above ever loses its atomic write.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        sleep(0.01) until (child_pid = recorded_pid(pid_path)) ||
                          Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert child_pid, "launcher did not record its descendant"
        assert runner_thread.join(2), "launcher waited for a descendant holding inherited streams"
        result = runner_thread.value
      ensure
        # Cleanup runs even when the body failed early, so this read has to
        # tolerate a missing or half-written file rather than raise over the
        # original failure.
        child_pid ||= recorded_pid(pid_path)
        begin
          Process.kill("TERM", child_pid) if child_pid
        rescue Errno::ESRCH
          # The child already exited and was reaped by the operating system.
        end
        runner_thread&.join(2)
      end
    end

    assert result.status.success?
    assert_empty result.stdout
    assert_empty result.stderr
  end

  def test_discard_output_rejects_stdin_data
    assert_raises(ArgumentError) do
      SequelAceRelease::CommandRunner.new.run(
        "/usr/bin/true",
        discard_output: true,
        stdin_data: "unexpected"
      )
    end
  end

  def test_explicitly_redacts_signed_download_urls_from_failures
    signed_url = "https://download.example.invalid/artifact?signature=secret-value"
    error = assert_raises(SequelAceRelease::CommandError) do
      SequelAceRelease::CommandRunner.new.run(
        "/usr/bin/false",
        signed_url,
        redact_arguments: [1]
      )
    end

    assert_includes error.message, "[REDACTED]"
    refute_includes error.message, signed_url
    refute_includes error.message, "secret-value"
  end

  def test_explicit_redaction_also_scrubs_captured_error_output
    signed_url = "https://download.example.invalid/artifact?signature=output-secret"
    error = assert_raises(SequelAceRelease::CommandError) do
      SequelAceRelease::CommandRunner.new.run(
        "/bin/sh",
        "-c",
        'printf "%s\n" "$1" >&2; exit 1',
        "redaction-test",
        signed_url,
        redact_arguments: [4]
      )
    end

    assert_includes error.message, "[REDACTED]"
    refute_includes error.message, signed_url
    refute_includes error.message, "output-secret"
  end

  # The pid reader is what keeps the launcher test from being flaky, and its
  # nil cases are the ones the happy path never reaches: the poll relies on
  # them to keep waiting, and cleanup relies on them not to raise over an
  # earlier failure.
  def test_recorded_pid_reports_nothing_until_a_pid_is_fully_written
    Dir.mktmpdir do |directory|
      path = File.join(directory, "child.pid")

      assert_nil recorded_pid(nil), "a nil path is not an error"
      assert_nil recorded_pid(path), "missing file"

      File.write(path, "")
      assert_nil recorded_pid(path), "created but not yet written"

      File.write(path, "   \n")
      assert_nil recorded_pid(path), "whitespace only"

      File.write(path, "not-a-pid")
      assert_nil recorded_pid(path), "unparseable"

      assert_nil recorded_pid(directory), "a directory is not a pid file"

      File.write(path, "4242\n")
      assert_equal 4242, recorded_pid(path), "trailing newline is tolerated"
    end
  end

  private

  # The pid recorded at `path`, or nil while it is absent, empty or not yet
  # fully written. Never raises: callers use it to decide whether to keep
  # waiting, and one of them runs during cleanup.
  def recorded_pid(path)
    return nil unless path

    contents = begin
      File.read(path)
    rescue Errno::ENOENT, Errno::EISDIR
      return nil
    end

    begin
      Integer(contents.strip)
    rescue ArgumentError
      nil
    end
  end
end
