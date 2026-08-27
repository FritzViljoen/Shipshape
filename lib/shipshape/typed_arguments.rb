# frozen_string_literal: true

module Shipshape
  # Holds `arguments-are-typed-at-construction` for this gem, and is what a consumer uses
  # to hold it for their own code.
  #
  # It **asserts and never coerces**. A mismatch raises `ArgumentError`, because it is the
  # caller's defect and not an answer anybody is waiting for. Past the guard nothing
  # re-checks: a failure at the guard is the caller's, a failure after it is ours.
  #
  # There is no macro. The initializer is written, and `typed(base_dir, String)` stays a
  # thing you can grep for — which is the whole of `code-is-written-not-generated`.
  module TypedArguments
    private

    def typed(value, type, allow_nil: false)
      return value if allow_nil && value.nil?
      return value if value.is_a?(type)

      raise ArgumentError, "expected #{type}, got #{value.class}: #{value.inspect}"
    end

    def typed_array(values, type, allow_empty: true)
      typed(values, Array)
      raise ArgumentError, "expected a non-empty Array of #{type}" if values.empty? && !allow_empty

      values.each { |value| typed(value, type) }
      values
    end

    # Keys and values are asserted separately, because a Hash whose keys are right and
    # whose values are not is the commoner mistake and the one a bare `Hash` check misses.
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
