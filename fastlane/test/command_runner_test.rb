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

  def test_can_run_a_gui_launcher_without_capture_pipes
    child_pid = nil
    pid_path = nil
    result = nil
    runner_thread = nil

    Dir.mktmpdir do |directory|
      begin
        pid_path = File.join(directory, "inherited-stream-child.pid")
        launcher = <<~'RUBY'
          child_pid = fork do
            $stdout.write("inherited output")
            $stderr.write("inherited error")
            sleep 5
          end
          File.write(ARGV.fetch(0), child_pid)
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
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        sleep(0.01) until File.file?(pid_path) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert File.file?(pid_path), "launcher did not record its descendant"
        child_pid = Integer(File.read(pid_path))
        assert runner_thread.join(2), "launcher waited for a descendant holding inherited streams"
        result = runner_thread.value
      ensure
        child_pid ||= Integer(File.read(pid_path)) if pid_path && File.file?(pid_path)
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
end
