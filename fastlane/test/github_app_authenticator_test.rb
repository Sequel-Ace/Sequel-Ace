# frozen_string_literal: true

require "test_helper"

class GitHubAppAuthenticatorTest < Minitest::Test
  def test_mints_a_repository_scoped_actions_only_installation_token
    key = OpenSSL::PKey::RSA.generate(2048)
    transport = FakeTransport.new([
      relay_installation,
      http_response(status: 201, body: {
        "token" => "installation-token",
        "expires_at" => "2026-08-09T17:00:00Z",
        "permissions" => { "actions" => "write", "metadata" => "read" },
        "repositories" => [{ "full_name" => "Sequel-Ace/Sequel-Ace" }]
      })
    ])
    authenticator = SequelAceRelease::GitHubAppAuthenticator.new(
      app_id: "12345",
      private_key: key.to_pem,
      transport: transport,
      clock: -> { Time.at(1_700_000_000) }
    )

    assert_equal "installation-token", authenticator.installation_token
    lookup, creation = transport.requests
    assert_equal "/repos/Sequel-Ace/Sequel-Ace/installation", lookup.fetch(:path)
    assert_equal "/app/installations/42/access_tokens", creation.fetch(:path)
    assert_equal ["Sequel-Ace"], creation.dig(:body, "repositories")
    assert_equal({ "actions" => "write" }, creation.dig(:body, "permissions"))
    refute creation.dig(:body, "permissions").key?("contents")
    refute creation.dig(:body, "permissions").key?("pull_requests")

    token = lookup.dig(:headers, "Authorization").delete_prefix("Bearer ")
    header_segment, payload_segment, signature_segment = token.split(".")
    assert_equal({ "alg" => "RS256", "typ" => "JWT" }, decode_segment(header_segment))
    payload = decode_segment(payload_segment)
    assert_equal "12345", payload.fetch("iss")
    assert_equal 1_699_999_940, payload.fetch("iat")
    assert_equal 1_700_000_540, payload.fetch("exp")
    assert key.public_key.verify(
      OpenSSL::Digest::SHA256.new,
      decode_bytes(signature_segment),
      "#{header_segment}.#{payload_segment}"
    )
  end

  def test_rejects_a_relay_app_installation_with_contents_authority
    key = OpenSSL::PKey::RSA.generate(2048)
    response = relay_installation
    response.body.fetch("permissions")["contents"] = "write"
    transport = FakeTransport.new([response])
    authenticator = SequelAceRelease::GitHubAppAuthenticator.new(
      app_id: "12345",
      private_key: key.to_pem,
      transport: transport
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      authenticator.installation_token
    end
    assert_includes error.message, "exceeds the Actions-only policy"
    assert_equal 1, transport.requests.length
  end

  def test_environment_base64_decoding_never_echoes_private_key_material
    secret = "not-a-private-key"
    environment = {
      "SA_WEBHOOK_GITHUB_APP_ID" => "12345",
      "SA_WEBHOOK_GITHUB_APP_PRIVATE_KEY" => Base64.strict_encode64(secret),
      "SA_WEBHOOK_GITHUB_APP_PRIVATE_KEY_BASE64" => "1"
    }

    error = assert_raises(SequelAceRelease::ValidationError) do
      SequelAceRelease::GitHubAppAuthenticator.from_env(environment)
    end
    refute_includes error.message, secret
    assert_includes error.message, "private key is invalid"
  end

  private

  def relay_installation
    http_response(body: {
      "id" => 42,
      "app_slug" => "sequel-ace-release-webhook",
      "repository_selection" => "selected",
      "permissions" => { "actions" => "write", "metadata" => "read" },
      "events" => [],
      "suspended_at" => nil
    })
  end

  def decode_segment(segment)
    JSON.parse(decode_bytes(segment))
  end

  def decode_bytes(segment)
    Base64.urlsafe_decode64(segment.ljust((segment.length + 3) / 4 * 4, "="))
  end
end
