# frozen_string_literal: true

module SequelAceRelease
  class Error < StandardError; end
  class ValidationError < Error; end
  class IntegrityError < ValidationError; end
  class CommandError < Error; end
  class APIError < Error
    attr_reader :status

    def initialize(message = nil, status: nil)
      super(message)
      @status = status
    end
  end
end
