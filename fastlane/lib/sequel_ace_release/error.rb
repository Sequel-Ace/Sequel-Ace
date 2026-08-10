# frozen_string_literal: true

module SequelAceRelease
  class Error < StandardError; end
  class ValidationError < Error; end
  class CommandError < Error; end
  class APIError < Error; end
end
