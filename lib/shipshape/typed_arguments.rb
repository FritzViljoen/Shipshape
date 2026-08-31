# frozen_string_literal: true

require "shipshape/boolean"

module Shipshape
  # Holds `arguments-are-typed-at-construction`, here and in a consumer's own code.
  module TypedArguments
    private

    def typed(value, type, allow_nil: false)
      return value if allow_nil && value.nil?
      return value if matches?(value, type)

      raise ArgumentError, "expected #{type}, got #{value.class}: #{value.inspect}"
    end

    def typed_array(values, type, allow_empty: true)
      typed(values, Array)
      raise ArgumentError, "expected a non-empty Array of #{type}" if values.empty? && !allow_empty

      values.each { |value| typed(value, type) }
      values
    end

    def matches?(value, type)
      return value == true || value == false if type.equal?(Boolean)

      value.is_a?(type)
    end

    def typed_hash(value, key_type, value_type)
      typed(value, Hash)
      value.each do |key, entry|
        typed(key, key_type)
        typed(entry, value_type)
      end
      value
    end
  end
end
