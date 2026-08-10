# frozen_string_literal: true

require "test_helper"

class AppStoreWebhookTest < Minitest::Test
  SECRET = "recorded-redacted-webhook-secret"

  def test_accepts_an_exact_ready_for_distribution_transition
    body = JSON.generate(version_state_payload(new_value: "READY_FOR_DISTRIBUTION"))
    result = verifier.verify_and_classify(body: body, signature: signature(body))

    assert_equal true, result.fetch("accepted")
    assert_equal true, result.fetch("dispatch")
    assert_equal "ready_for_distribution", result.fetch("reason")
    assert_equal "version-id", result.fetch("version_id")
    assert_equal "event-id", result.fetch("event_id")
  end

  def test_ignores_a_valid_transition_that_is_not_live
    body = JSON.generate(version_state_payload(new_value: "PENDING_APPLE_RELEASE"))
    result = verifier.verify_and_classify(body: body, signature: signature(body))

    assert_equal false, result.fetch("dispatch")
    assert_equal "ignored_non_ready_state", result.fetch("reason")
  end

  def test_ignores_apples_signed_ping_shape_without_requiring_an_event_id
    body = JSON.generate({
      "data" => {
        "type" => "webhookPings",
        "relationships" => {
          "webhook" => { "data" => { "type" => "webhooks", "id" => "webhook-id" } }
        }
      }
    })
    result = verifier.verify_and_classify(body: body, signature: signature(body))

    assert_equal false, result.fetch("dispatch")
    assert_equal "ignored_event_type", result.fetch("reason")
    refute result.key?("event_id")
  end

  def test_rejects_a_signature_for_different_raw_bytes
    body = JSON.generate(version_state_payload)
    error = assert_raises(SequelAceRelease::ValidationError) do
      verifier.verify_and_classify(body: "#{body}\n", signature: signature(body))
    end

    assert_includes error.message, "signature is invalid"
    refute_includes error.message, SECRET
  end

  def test_rejects_malformed_state_event_relationships
    payload = version_state_payload
    payload.fetch("data").delete("relationships")
    body = JSON.generate(payload)

    error = assert_raises(SequelAceRelease::ValidationError) do
      verifier.verify_and_classify(body: body, signature: signature(body))
    end
    assert_includes error.message, "version ID"
  end

  def test_rejects_a_signed_non_object_payload_as_a_validation_error
    body = JSON.generate(["unexpected"])

    error = assert_raises(SequelAceRelease::ValidationError) do
      verifier.verify_and_classify(body: body, signature: signature(body))
    end
    assert_includes error.message, "payload is malformed"
  end

  def test_rejects_an_authentic_but_stale_live_event
    body = JSON.generate(version_state_payload(new_value: "READY_FOR_DISTRIBUTION"))
    stale_verifier = SequelAceRelease::AppStoreWebhook.new(
      secret: SECRET,
      clock: -> { Time.iso8601("2026-08-10T16:00:01Z") }
    )

    error = assert_raises(SequelAceRelease::ValidationError) do
      stale_verifier.verify_and_classify(body: body, signature: signature(body))
    end
    assert_includes error.message, "too old"
  end

  def test_event_ledger_claims_an_event_only_once
    Dir.mktmpdir do |directory|
      path = File.join(directory, "events.jsonl")
      ledger = SequelAceRelease::WebhookEventLedger.new(
        path: path,
        clock: -> { Time.iso8601("2026-08-09T16:05:00Z") }
      )

      assert_equal true, ledger.claim(event_id: "event-id", fingerprint: "a" * 64)
      assert_equal false, ledger.claim(event_id: "event-id", fingerprint: "a" * 64)
    end
  end

  def test_event_ledger_rejects_reuse_of_an_event_id_with_different_signed_bytes
    Dir.mktmpdir do |directory|
      path = File.join(directory, "events.jsonl")
      ledger = SequelAceRelease::WebhookEventLedger.new(path: path)
      ledger.claim(event_id: "event-id", fingerprint: "a" * 64)

      error = assert_raises(SequelAceRelease::ValidationError) do
        ledger.claim(event_id: "event-id", fingerprint: "b" * 64)
      end
      assert_includes error.message, "reused with different signed bytes"
    end
  end

  private

  def verifier
    SequelAceRelease::AppStoreWebhook.new(
      secret: SECRET,
      clock: -> { Time.iso8601("2026-08-09T16:05:00Z") }
    )
  end

  def signature(body)
    digest = OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)
    "hmacsha256=#{digest}"
  end

  def version_state_payload(new_value: "READY_FOR_DISTRIBUTION")
    {
      "data" => {
        "type" => "appStoreVersionAppVersionStateUpdated",
        "id" => "event-id",
        "attributes" => {
          "newValue" => new_value,
          "oldValue" => "PENDING_APPLE_RELEASE",
          "timestamp" => "2026-08-09T16:00:00Z"
        },
        "relationships" => {
          "instance" => { "data" => { "type" => "appStoreVersions", "id" => "version-id" } }
        }
      }
    }
  end
end
