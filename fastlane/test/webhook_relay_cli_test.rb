# frozen_string_literal: true

require "test_helper"

class WebhookRelayCLITest < Minitest::Test
  def test_live_event_uses_the_app_token_and_sends_only_redacted_identity_fields
    secret = "redacted-webhook-secret"
    body = JSON.generate(version_state_payload(new_value: "READY_FOR_DISTRIBUTION"))
    signature = "hmacsha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    out = StringIO.new
    err = StringIO.new
    authenticator = Object.new
    authenticator.define_singleton_method(:installation_token) { "installation-token" }
    dispatched = nil
    github = Object.new
    github.define_singleton_method(:dispatch_workflow) do |**arguments|
      dispatched = arguments
      true
    end

    Dir.mktmpdir do |directory|
      path = File.join(directory, "payload.json")
      ledger = File.join(directory, "events.jsonl")
      File.binwrite(path, body)
      SequelAceRelease::GitHubAppAuthenticator.stub(:from_env, authenticator) do
        SequelAceRelease::GitHubClient.stub(:new, lambda { |token:|
          raise unless token == "installation-token"

          github
        }) do
          status = SequelAceRelease::CLI.run(
            ["relay-webhook", "--payload", path, "--app-id", "1518036000", "--event-ledger", ledger],
            out: out,
            err: err,
            env: {
              "SA_ASC_WEBHOOK_SECRET" => secret,
              "SA_ASC_WEBHOOK_SIGNATURE" => signature
            }
          )
          assert_equal 0, status
        end
      end
    end

    assert_empty err.string
    assert_equal "release_finalize.yml", dispatched.fetch(:workflow)
    assert_equal "main", dispatched.fetch(:ref)
    inputs = dispatched.fetch(:inputs)
    assert_equal "1518036000", inputs.fetch("app_id")
    assert_equal "version-id", inputs.fetch("version_id")
    assert_equal "READY_FOR_DISTRIBUTION", inputs.fetch("new_value")
    refute_includes JSON.generate(inputs), secret
    assert_equal "sent", JSON.parse(out.string).fetch("workflow_dispatch")
  end

  def test_valid_non_live_event_exits_without_needing_github_credentials
    secret = "redacted-webhook-secret"
    body = JSON.generate(version_state_payload(new_value: "PENDING_APPLE_RELEASE"))
    signature = "hmacsha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    out = StringIO.new
    err = StringIO.new

    Dir.mktmpdir do |directory|
      path = File.join(directory, "payload.json")
      ledger = File.join(directory, "events.jsonl")
      File.binwrite(path, body)
      status = SequelAceRelease::CLI.run(
        ["relay-webhook", "--payload", path, "--app-id", "1518036000", "--event-ledger", ledger],
        out: out,
        err: err,
        env: {
          "SA_ASC_WEBHOOK_SECRET" => secret,
          "SA_ASC_WEBHOOK_SIGNATURE" => signature
        }
      )

      assert_equal 0, status
      assert_empty err.string
      result = JSON.parse(out.string)
      assert_equal false, result.fetch("dispatch")
      assert_equal "not_required", result.fetch("workflow_dispatch")
    end
  end

  def test_relay_refuses_the_alpha_app_before_reading_a_payload
    out = StringIO.new
    err = StringIO.new
    status = SequelAceRelease::CLI.run(
      ["relay-webhook", "--payload", "/does/not/exist", "--app-id", "1594104035"],
      out: out,
      err: err,
      env: {}
    )

    assert_equal 1, status
    assert_includes err.string, "Production App Store app"
  end

  def test_relay_bounds_the_payload_read_before_signature_verification
    out = StringIO.new
    err = StringIO.new

    Dir.mktmpdir do |directory|
      path = File.join(directory, "oversized-payload.json")
      ledger = File.join(directory, "events.jsonl")
      File.binwrite(path, "x" * (SequelAceRelease::AppStoreWebhook::MAX_BODY_BYTES + 2))
      status = SequelAceRelease::CLI.run(
        ["relay-webhook", "--payload", path, "--app-id", "1518036000", "--event-ledger", ledger],
        out: out,
        err: err,
        env: {
          "SA_ASC_WEBHOOK_SECRET" => "redacted-webhook-secret",
          "SA_ASC_WEBHOOK_SIGNATURE" => "not-read-for-an-oversized-payload"
        }
      )

      assert_equal 1, status
      assert_empty out.string
      assert_includes err.string, "body exceeds the size limit"
    end
  end

  def test_duplicate_signed_event_is_consumed_without_a_second_workflow_dispatch
    secret = "redacted-webhook-secret"
    body = JSON.generate(version_state_payload(new_value: "READY_FOR_DISTRIBUTION"))
    signature = "hmacsha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    authenticator = Object.new
    authenticator.define_singleton_method(:installation_token) { "installation-token" }
    dispatch_count = 0
    github = Object.new
    github.define_singleton_method(:dispatch_workflow) do |**_arguments|
      dispatch_count += 1
      true
    end

    Dir.mktmpdir do |directory|
      payload = File.join(directory, "payload.json")
      ledger = File.join(directory, "events.jsonl")
      File.binwrite(payload, body)
      environment = {
        "SA_ASC_WEBHOOK_SECRET" => secret,
        "SA_ASC_WEBHOOK_SIGNATURE" => signature
      }
      outputs = 2.times.map do
        out = StringIO.new
        err = StringIO.new
        SequelAceRelease::GitHubAppAuthenticator.stub(:from_env, authenticator) do
          SequelAceRelease::GitHubClient.stub(:new, github) do
            status = SequelAceRelease::CLI.run(
              ["relay-webhook", "--payload", payload, "--app-id", "1518036000", "--event-ledger", ledger],
              out: out,
              err: err,
              env: environment
            )
            assert_equal 0, status
            assert_empty err.string
          end
        end
        JSON.parse(out.string)
      end

      assert_equal "sent", outputs.first.fetch("workflow_dispatch")
      assert_equal "duplicate_ignored", outputs.last.fetch("workflow_dispatch")
      assert_equal 1, dispatch_count
      assert_equal 0, File.stat(ledger).mode & 0o077
    end
  end


  private

  def version_state_payload(new_value:)
    {
      "data" => {
        "type" => "appStoreVersionAppVersionStateUpdated",
        "id" => "event-id",
        "attributes" => {
          "newValue" => new_value,
          "oldValue" => "WAITING_FOR_REVIEW",
          "timestamp" => Time.now.utc.iso8601
        },
        "relationships" => {
          "instance" => { "data" => { "id" => "version-id" } }
        }
      }
    }
  end
end
