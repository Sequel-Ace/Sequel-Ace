# frozen_string_literal: true

require "json"
require "openssl"
require "time"

module SequelAceRelease
  class AppStoreWebhook
    MAX_BODY_BYTES = 1_048_576
    MAX_EVENT_AGE_SECONDS = 24 * 60 * 60
    MAX_FUTURE_SKEW_SECONDS = 5 * 60
    VERSION_STATE_EVENT = "appStoreVersionAppVersionStateUpdated"
    READY_STATE = "READY_FOR_DISTRIBUTION"
    SAFE_IDENTIFIER = /\A[A-Za-z0-9._:-]{1,255}\z/.freeze
    SAFE_STATE = /\A[A-Z][A-Z0-9_]{0,127}\z/.freeze

    def initialize(secret:, clock: -> { Time.now })
      raise ValidationError, "App Store webhook secret is required" if secret.to_s.empty?

      @secret = secret
      @clock = clock
    end

    def verify_and_classify(body:, signature:)
      raw_body = body.to_s.b
      raise ValidationError, "App Store webhook body is empty" if raw_body.empty?
      raise ValidationError, "App Store webhook body exceeds the size limit" if raw_body.bytesize > MAX_BODY_BYTES

      verify_signature!(raw_body, signature)
      payload = JSON.parse(raw_body)
      unless payload.is_a?(Hash)
        raise ValidationError, "App Store webhook payload is malformed"
      end
      data = payload["data"]
      unless data.is_a?(Hash)
        raise ValidationError, "App Store webhook payload is malformed"
      end

      event_type = safe_identifier!(data["type"], "event type")
      unless event_type == VERSION_STATE_EVENT
        ignored = {
          "accepted" => true,
          "dispatch" => false,
          "reason" => "ignored_event_type",
          "event_type" => event_type
        }
        ignored["event_id"] = safe_identifier!(data["id"], "event ID") if data.key?("id")
        return ignored
      end

      event_id = safe_identifier!(data["id"], "event ID")
      attributes = data["attributes"]
      unless attributes.is_a?(Hash)
        raise ValidationError, "App Store version-state webhook attributes are malformed"
      end
      new_value = safe_state!(attributes["newValue"], "new state")
      old_value = safe_state!(attributes["oldValue"], "old state")
      timestamp = attributes["timestamp"].to_s
      begin
        event_time = Time.iso8601(timestamp)
      rescue ArgumentError
        raise ValidationError, "App Store webhook timestamp is malformed"
      end
      now = @clock.call
      if event_time < now - MAX_EVENT_AGE_SECONDS
        raise ValidationError, "App Store webhook event is too old"
      end
      if event_time > now + MAX_FUTURE_SKEW_SECONDS
        raise ValidationError, "App Store webhook event timestamp is in the future"
      end
      relationships = data["relationships"]
      instance = relationships["instance"] if relationships.is_a?(Hash)
      instance_data = instance["data"] if instance.is_a?(Hash)
      version_id_value = instance_data["id"] if instance_data.is_a?(Hash)
      version_id = safe_identifier!(version_id_value, "App Store version ID")

      {
        "accepted" => true,
        "dispatch" => new_value == READY_STATE,
        "reason" => new_value == READY_STATE ? "ready_for_distribution" : "ignored_non_ready_state",
        "event_id" => event_id,
        "event_type" => event_type,
        "version_id" => version_id,
        "new_value" => new_value,
        "old_value" => old_value,
        "timestamp" => timestamp
      }
    rescue JSON::ParserError
      raise ValidationError, "App Store webhook body is not valid JSON"
    end

    private

    def verify_signature!(body, signature)
      match = signature.to_s.match(/\Ahmacsha256=([0-9a-f]{64})\z/)
      raise ValidationError, "App Store webhook signature is malformed" unless match

      expected = OpenSSL::HMAC.hexdigest("SHA256", @secret, body)
      return if OpenSSL.fixed_length_secure_compare(expected, match[1])

      raise ValidationError, "App Store webhook signature is invalid"
    end

    def safe_identifier!(value, label)
      text = value.to_s
      raise ValidationError, "App Store webhook #{label} is malformed" unless text.match?(SAFE_IDENTIFIER)

      text
    end

    def safe_state!(value, label)
      text = value.to_s
      raise ValidationError, "App Store webhook #{label} is malformed" unless text.match?(SAFE_STATE)

      text
    end
  end

  class WebhookEventLedger
    MAX_LEDGER_BYTES = 1_048_576
    MAX_ENTRIES = 4_096
    RETENTION_SECONDS = AppStoreWebhook::MAX_EVENT_AGE_SECONDS + AppStoreWebhook::MAX_FUTURE_SKEW_SECONDS
    SAFE_FINGERPRINT = /\A[0-9a-f]{64}\z/.freeze

    def initialize(path:, clock: -> { Time.now })
      raise ValidationError, "App Store webhook event ledger path is required" if path.to_s.empty?

      @path = File.expand_path(path)
      @clock = clock
    end

    # Claim before dispatching. If the following network request has an
    # ambiguous outcome, the event remains consumed and the authorized manual
    # finalizer is the recovery path; automatically replaying a privileged wake
    # up would be less safe.
    def claim(event_id:, fingerprint:)
      unless event_id.to_s.match?(AppStoreWebhook::SAFE_IDENTIFIER)
        raise ValidationError, "App Store webhook event ledger ID is malformed"
      end
      unless fingerprint.to_s.match?(SAFE_FINGERPRINT)
        raise ValidationError, "App Store webhook event fingerprint is malformed"
      end

      flags = File::RDWR | File::CREAT
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      File.open(@path, flags, 0o600) do |file|
        raise ValidationError, "App Store webhook event ledger is not a regular file" unless file.stat.file?
        unless (file.stat.mode & 0o077).zero?
          raise ValidationError, "App Store webhook event ledger permissions must be 0600 or stricter"
        end
        raise ValidationError, "could not lock App Store webhook event ledger" unless file.flock(File::LOCK_EX)

        entries = read_entries(file)
        cutoff = @clock.call - RETENTION_SECONDS
        entries.select! { |entry| Time.iso8601(entry.fetch("claimed_at")) >= cutoff }
        existing = entries.find { |entry| entry.fetch("event_id") == event_id }
        if existing
          unless existing.fetch("fingerprint") == fingerprint
            raise ValidationError, "App Store webhook event ID was reused with different signed bytes"
          end
          return false
        end

        entries << {
          "event_id" => event_id,
          "fingerprint" => fingerprint,
          "claimed_at" => @clock.call.utc.iso8601(6)
        }
        raise ValidationError, "App Store webhook event ledger reached its entry limit" if entries.length > MAX_ENTRIES

        serialized = entries.map { |entry| JSON.generate(entry) }.join("\n") + "\n"
        if serialized.bytesize > MAX_LEDGER_BYTES
          raise ValidationError, "App Store webhook event ledger exceeds the size limit"
        end
        file.rewind
        file.write(serialized)
        file.truncate(file.pos)
        file.flush
        file.fsync
        true
      end
    rescue Errno::ELOOP
      raise ValidationError, "App Store webhook event ledger must not be a symbolic link"
    rescue Errno::ENOENT, Errno::EACCES => error
      raise ValidationError, "App Store webhook event ledger is unavailable: #{error.class}"
    end

    private

    def read_entries(file)
      file.rewind
      contents = file.read(MAX_LEDGER_BYTES + 1) || ""
      raise ValidationError, "App Store webhook event ledger exceeds the size limit" if contents.bytesize > MAX_LEDGER_BYTES
      return [] if contents.empty?

      contents.lines.map do |line|
        entry = JSON.parse(line)
        unless entry.is_a?(Hash) &&
               entry["event_id"].to_s.match?(AppStoreWebhook::SAFE_IDENTIFIER) &&
               entry["fingerprint"].to_s.match?(SAFE_FINGERPRINT)
          raise ValidationError, "App Store webhook event ledger is malformed"
        end
        Time.iso8601(entry.fetch("claimed_at"))
        entry
      end
    rescue JSON::ParserError, KeyError, ArgumentError
      raise ValidationError, "App Store webhook event ledger is malformed"
    end
  end
end
