# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module SequelAceRelease
  class HTTPTransport
    Response = Struct.new(:status, :headers, :body, keyword_init: true)
    RETRYABLE = [429, 500, 502, 503, 504].freeze

    def initialize(base_url:, default_headers: {}, max_attempts: 4)
      @base_url = base_url
      @default_headers = default_headers
      @max_attempts = max_attempts
    end

    def request(method, path, query: nil, body: nil, headers: {})
      uri = build_uri(path, query)
      attempt = 0
      loop do
        attempt += 1
        begin
          response = perform(method, uri, body, @default_headers.merge(headers))
        rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED => error
          if attempt >= @max_attempts
            raise APIError, "API request failed after #{attempt} attempts: #{error.class}"
          end
          sleep([attempt, 5].min)
          next
        end
        parsed = parse_body(response.body)
        unless RETRYABLE.include?(response.code.to_i) && attempt < @max_attempts
          return Response.new(status: response.code.to_i, headers: response.to_hash, body: parsed)
        end

        sleep([attempt, 5].min)
      end
    end

    private

    def build_uri(path, query)
      uri = URI.join(@base_url, path)
      uri.query = URI.encode_www_form(query) if query && !query.empty?
      uri
    end

    def perform(method, uri, body, headers)
      request_class = {
        "GET" => Net::HTTP::Get,
        "POST" => Net::HTTP::Post,
        "PATCH" => Net::HTTP::Patch,
        "PUT" => Net::HTTP::Put,
        "DELETE" => Net::HTTP::Delete
      }.fetch(method.to_s.upcase) { raise ValidationError, "unsupported HTTP method: #{method}" }
      request = request_class.new(uri)
      headers.each { |key, value| request[key] = value }
      unless body.nil?
        request.body = if body.is_a?(String) && headers["Content-Type"] != "application/json"
                         body
                       else
                         JSON.generate(body)
                       end
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 60) do |http|
        http.request(request)
      end
    end

    def parse_body(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
