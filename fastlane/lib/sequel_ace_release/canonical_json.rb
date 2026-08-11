# frozen_string_literal: true

require "json"

module SequelAceRelease
  module CanonicalJSON
    module_function

    def dump(value)
      JSON.generate(sort(value))
    end

    def pretty(value)
      JSON.pretty_generate(sort(value)) + "\n"
    end

    def sort(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), result|
          result[key.to_s] = sort(child)
        end.sort.to_h
      when Array
        value.map { |child| sort(child) }
      else
        value
      end
    end
  end
end
