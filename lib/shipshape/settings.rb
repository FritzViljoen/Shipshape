# frozen_string_literal: true

require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # The seam: a cop's configuration is YAML somebody typed, parsed and asserted here once and
  # never re-examined. `input-is-parsed-at-the-seam`, applied to this gem's one untrusted input.
  class Settings
    include TypedArguments

    SISTER_ERROR = "Shipshape: Matrix row %<kind>s lists %<sister>s, which is a sister of " \
                   "it. No kind calls a sister, so a row naming one is a contradiction " \
                   "rather than a permission."

    UNKNOWN_KIND_ERROR = "Shipshape: Matrix names %<kind>s, which no Kinds entry declares. " \
                         "A matrix row for a kind that does not exist permits nothing and " \
                         "hides a typo."

    UNKNOWN_BASE_KIND_ERROR = "Shipshape: BaseClasses names %<kind>s, which no Kinds entry " \
                              "declares. A base class mapped to a kind that does not exist " \
                              "classifies nothing and hides a typo."

    attr_reader :kinds, :matrix, :base_classes, :sisters

    def initialize(kinds:, matrix:, base_classes: {}, sisters: [])
      @kinds = typed_hash(kinds, String, Array)
      @matrix = typed_hash(matrix, String, Array)
      @base_classes = typed_hash(base_classes, String, Array)
      @sisters = typed_array(sisters, Array)

      assert_globs_are_strings
      refuse_rows_naming_a_sister
      refuse_rows_naming_an_undeclared_kind
      refuse_base_classes_for_an_undeclared_kind
    end

    # Every kind is its own sister; a declared group adds the rest.
    def sisters_of(kind)
      group = sisters.find { |names| names.include?(kind) } || []

      ([kind] + group).uniq
    end

    # The superclass decides the kind, which is why two kinds may share a glob.
    def kind_of_base_class(name)
      base_classes.each do |kind, names|
        return kind if names.include?(name)
      end
      nil
    end

    LAYOUT_COP = "Shipshape/CallGraph"

    def self.from_cop_config(cop_config)
      new(
        kinds: cop_config.fetch("Kinds", {}),
        matrix: cop_config.fetch("Matrix", {}),
        base_classes: cop_config.fetch("BaseClasses", {}),
        sisters: cop_config.fetch("Sisters", []),
      )
    end

    # The layout — which paths hold which kind — is declared **once**, on the call-graph
    # cop, and every other cop reads it from there. Repeating it per cop would be a second
    # copy of one fact, and the copy is the one that goes stale.
    def self.layout(config)
      from_cop_config(config.for_cop(LAYOUT_COP))
    end

    def reachable_from(kind)
      matrix.fetch(kind, [])
    end

    private

    def assert_globs_are_strings
      kinds.each_value { |globs| typed_array(globs, String) }
      base_classes.each_value { |names| typed_array(names, String) }
      sisters.each { |group| typed_array(group, String) }
    end

    def refuse_rows_naming_a_sister
      matrix.each do |kind, reachable|
        sister = (reachable & sisters_of(kind)).first
        raise Error, format(SISTER_ERROR, kind: kind, sister: sister) if sister
      end
    end

    def refuse_rows_naming_an_undeclared_kind
      (matrix.keys + matrix.values.flatten).uniq.each do |kind|
        raise Error, format(UNKNOWN_KIND_ERROR, kind: kind) unless kinds.key?(kind)
      end
    end

    def refuse_base_classes_for_an_undeclared_kind
      base_classes.each_key do |kind|
        raise Error, format(UNKNOWN_BASE_KIND_ERROR, kind: kind) unless kinds.key?(kind)
      end
    end
  end
end
