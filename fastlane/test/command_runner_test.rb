# frozen_string_literal: true

require "test_helper"

class CommandRunnerTest < Minitest::Test
  def test_can_run_a_gui_launcher_without_capture_pipes
    result = SequelAceRelease::CommandRunner.new.run(
      RbConfig.ruby,
      "-e",
      '$stdout.write("captured output"); $stderr.write("captured error")',
      discard_output: true
    )

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
