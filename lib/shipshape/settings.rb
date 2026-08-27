# frozen_string_literal: true

require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # The seam. A cop's configuration is YAML somebody typed, so it is parsed and asserted
  # here, once, and never re-examined afterwards — `input-is-parsed-at-the-seam` applied to
  # the one untrusted input this gem has.
  #
  # Everything past this class is handed real values. Nothing downstream calls `fetch` on a
  # raw config hash or wonders whether a key is a String or a Symbol.
  #
  # It bounces rather than defaulting. A silent fallback here would mean a cop that reports
  # zero offences because its configuration was misspelled, which is the exact
  # coverage-shaped hole `nothing-fails-quietly` exists to close.
  class Settings
    include TypedArguments

    # A glob's wildcards must all be at the tail. Everything before the first one is read as
    # an autoload root, which is how a constant name is turned back into a path — so
    # `app/*/queries/**/*.rb` would resolve constants against `app` and quietly match
    # nothing.
    GLOB_ERROR = "Shipshape: kind %<kind>s has glob %<glob>s, whose wildcards are not all " \
                 "at the end. The part before the first wildcard is read as an autoload " \
                 "root, so this glob would resolve no constants at all."

    SISTER_ERROR = "Shipshape: Matrix row %<kind>s lists itself. No kind calls its own " \
                   "kind, so a row naming itself is a contradiction rather than a " \
                   "permission."

    UNKNOWN_KIND_ERROR = "Shipshape: Matrix names %<kind>s, which no Kinds entry declares. " \
                         "A matrix row for a kind that does not exist permits nothing and " \
                         "hides a typo."

    attr_reader :kinds, :matrix

    def initialize(kinds:, matrix:)
      @kinds = typed_hash(kinds, String, Array)
      @matrix = typed_hash(matrix, String, Array)

      refuse_globs_with_a_wildcard_in_the_middle
      refuse_rows_that_name_themselves
      refuse_rows_naming_an_undeclared_kind
    end

    def self.from_cop_config(cop_config)
      new(kinds: cop_config.fetch("Kinds", {}), matrix: cop_config.fetch("Matrix", {}))
    end

    def reachable_from(kind)
      matrix.fetch(kind, [])
    end

    private

    def refuse_globs_with_a_wildcard_in_the_middle
      kinds.each do |kind, globs|
        typed_array(globs, String).each do |glob|
          next if wildcards_are_all_at_the_end?(glob)

          raise Error, format(GLOB_ERROR, kind: kind, glob: glob)
        end
      end
    end

    def wildcards_are_all_at_the_end?(glob)
      segments = glob.split("/")
      first = segments.index { |segment| segment.include?("*") }
      return true if first.nil?

      segments[first..-1].all? { |segment| segment.include?("*") }
    end

    def refuse_rows_that_name_themselves
      matrix.each do |kind, reachable|
        raise Error, format(SISTER_ERROR, kind: kind) if reachable.include?(kind)
      end
    end

    def refuse_rows_naming_an_undeclared_kind
      (matrix.keys + matrix.values.flatten).uniq.each do |kind|
        raise Error, format(UNKNOWN_KIND_ERROR, kind: kind) unless kinds.key?(kind)
      end
    end
  end
end
