# frozen_string_literal: true

require "date"
require "shipshape/boolean"

module Shipshape
  # Holds `arguments-are-typed-at-construction` and the runtime half of `a-time-names-its-zone`.
  module TypedArguments
    private

    def typed(value, type, allow_nil: false)
      return value if allow_nil && value.nil?
      return value if matches?(value, type)

      raise ArgumentError, mismatch_message(value, type)
    end

    def mismatch_message(value, type)
      return "expected #{type}, got #{value.class}: #{value.inspect}" unless type == Time || type == DateTime

      "expected a zoned #{type} (e.g. ActiveSupport::TimeWithZone), got #{value.class} " \
        "with no zone: #{value.inspect}"
    end

    def typed_array(values, type, allow_empty: true)
      typed(values, Array)
      raise ArgumentError, "expected a non-empty Array of #{type}" if values.empty? && !allow_empty

      values.each { |value| typed(value, type) }
      values
    end

    # `typed(value, Symbol)` accepts any Symbol — weaker than the closed vocabulary a status,
    # kind or currency code actually is. `allowed` is a plain Array, checked by membership.
    def typed_enum(value, allowed)
      typed(allowed, Array)
      return value if allowed.include?(value)

      raise ArgumentError, "expected one of #{allowed.inspect}, got #{value.inspect}"
    end

    def matches?(value, type)
      return value == true || value == false if type.equal?(Boolean)
      return value.is_a?(Date) && !value.is_a?(DateTime) if type == Date
      return zoned_moment?(value) if type == Time || type == DateTime

      value.is_a?(type)
    end

    # No ActiveSupport dependency here (unlike the installed template) — `defined?` avoids `NameError`.
    def zoned_moment?(value)
      defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone)
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
