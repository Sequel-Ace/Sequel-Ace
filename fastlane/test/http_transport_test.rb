# frozen_string_literal: true

require "test_helper"

class HTTPTransportTest < Minitest::Test
  NetResponse = Struct.new(:code, :body, :headers) do
    def to_hash
      headers || {}
    end
  end

  class SequenceTransport < SequelAceRelease::HTTPTransport
    attr_reader :attempts

    def initialize(responses)
      super(base_url: "https://example.invalid/", max_attempts: 4)
      @responses = responses
      @attempts = 0
    end

    private

    def perform(*_arguments)
      @attempts += 1
      @responses.shift || raise("missing response fixture")
    end

    def sleep(_seconds); end
  end

  def test_retries_rate_limits_and_returns_the_successful_json_response
    transport = SequenceTransport.new([
      NetResponse.new("429", '{"message":"rate limited"}', {}),
      NetResponse.new("200", '{"ok":true}', {})
    ])

    response = transport.request("GET", "/resource")
    assert_equal 200, response.status
    assert_equal({ "ok" => true }, response.body)
    assert_equal 2, transport.attempts
  end

  def test_preserves_a_malformed_non_json_response_for_safe_error_reporting
    transport = SequenceTransport.new([
      NetResponse.new("502", "not-json", {}),
      NetResponse.new("502", "still-not-json", {}),
      NetResponse.new("502", "malformed", {}),
      NetResponse.new("502", "final-malformed", {})
    ])

    response = transport.request("GET", "/resource")
    assert_equal 502, response.status
    assert_equal "final-malformed", response.body
    assert_equal 4, transport.attempts
  end

  def test_network_failures_use_the_same_bounded_retry_counter
    transport = SequenceTransport.new([
      -> { raise Errno::ECONNRESET },
      NetResponse.new("200", '{"recovered":true}', {})
    ])
    def transport.perform(*_arguments)
      @attempts += 1
      value = @responses.shift || raise("missing response fixture")
      value.respond_to?(:call) ? value.call : value
    end

    response = transport.request("GET", "/resource")
    assert_equal({ "recovered" => true }, response.body)
    assert_equal 2, transport.attempts
  end
end
