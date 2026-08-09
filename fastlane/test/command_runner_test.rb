# frozen_string_literal: true

require "test_helper"

class CommandRunnerTest < Minitest::Test
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
end
