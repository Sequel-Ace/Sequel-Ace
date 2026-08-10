# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module SequelAceRelease
  class GitHubAppAuthenticator
    API_URL = "https://api.github.com/"
    RELAY_PERMISSIONS = { "actions" => "write", "metadata" => "read" }.freeze

    def initialize(app_id:, private_key:, repository: Config::REPOSITORY, transport: nil, clock: -> { Time.now })
      raise ValidationError, "GitHub App ID is required" unless app_id.to_s.match?(/\A[1-9]\d*\z/)
      raise ValidationError, "GitHub App private key is required" if private_key.to_s.empty?

      @app_id = app_id.to_s
      @private_key = parse_private_key(private_key)
      @repository = repository
      @clock = clock
      @transport = transport || HTTPTransport.new(
        base_url: API_URL,
        default_headers: {
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent" => "sequel-ace-release-webhook-relay"
        }
      )
    end

    def self.from_env(environment = ENV, **options)
      private_key = environment["SA_WEBHOOK_GITHUB_APP_PRIVATE_KEY"]
      if environment["SA_WEBHOOK_GITHUB_APP_PRIVATE_KEY_BASE64"] == "1" && !private_key.to_s.empty?
        private_key = Base64.strict_decode64(private_key)
      end
      new(
        app_id: environment["SA_WEBHOOK_GITHUB_APP_ID"],
        private_key: private_key,
        **options
      )
    rescue ArgumentError
      raise ValidationError, "GitHub App private key is not valid base64"
    end

    def installation_token
      authorization = { "Authorization" => "Bearer #{jwt}" }
      installation = ensure_response!(
        @transport.request("GET", "/repos/#{@repository}/installation", headers: authorization),
        [200],
        "installation lookup"
      )
      verify_relay_installation!(installation)
      installation_id = Integer(installation.fetch("id"))
      raise ValidationError, "GitHub App installation ID is malformed" unless installation_id.positive?

      repository_name = @repository.split("/", 2).fetch(1)
      response = ensure_response!(
        @transport.request(
          "POST",
          "/app/installations/#{installation_id}/access_tokens",
          body: {
            "repositories" => [repository_name],
            "permissions" => { "actions" => "write" }
          },
          headers: authorization.merge("Content-Type" => "application/json")
        ),
        [201],
        "installation token creation"
      )
      token = response.fetch("token").to_s
      raise ValidationError, "GitHub App returned an empty installation token" if token.empty?
      unless response["permissions"] == RELAY_PERMISSIONS
        raise ValidationError, "GitHub webhook App returned permissions outside the Actions-only policy"
      end
      repositories = Array(response["repositories"])
      unless repositories.length == 1 && repositories.first.is_a?(Hash) && repositories.first["full_name"] == @repository
        raise ValidationError, "GitHub webhook App token is not restricted to the expected repository"
      end

      token
    rescue KeyError, ArgumentError, TypeError
      raise ValidationError, "GitHub App authentication response is malformed"
    end

    private

    def parse_private_key(value)
      key = OpenSSL::PKey::RSA.new(value)
      raise ValidationError, "GitHub App private key is not an RSA private key" unless key.private?

      key
    rescue OpenSSL::PKey::PKeyError, OpenSSL::PKey::RSAError
      raise ValidationError, "GitHub App private key is invalid"
    end

    def jwt
      now = @clock.call.to_i
      header = { "alg" => "RS256", "typ" => "JWT" }
      payload = { "iat" => now - 60, "exp" => now + 540, "iss" => @app_id }
      encoded = [header, payload].map { |value| base64url(JSON.generate(value)) }.join(".")
      signature = @private_key.sign(OpenSSL::Digest::SHA256.new, encoded)
      "#{encoded}.#{base64url(signature)}"
    end

    def verify_relay_installation!(installation)
      unless installation["permissions"] == RELAY_PERMISSIONS &&
             installation["repository_selection"] == "selected" &&
             Array(installation["events"]).empty? &&
             installation["suspended_at"].nil?
        raise ValidationError, "GitHub webhook App installation exceeds the Actions-only policy"
      end
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end

    def ensure_response!(response, expected, operation)
      return response.body if expected.include?(response.status) && response.body.is_a?(Hash)

      raise APIError, "GitHub App #{operation} failed with HTTP #{response.status}"
    end
  end
end
