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

    SISTER_ERROR = "Shipshape: Matrix row %<kind>s lists %<sister>s, which is a sister of " \
                   "it. No kind calls a sister, so a row naming one is a contradiction " \
                   "rather than a permission."

    UNKNOWN_KIND_ERROR = "Shipshape: Matrix names %<kind>s, which no Kinds entry declares. " \
                         "A matrix row for a kind that does not exist permits nothing and " \
                         "hides a typo."

    UNKNOWN_BASE_KIND_ERROR = "Shipshape: BaseClasses names %<kind>s, which no Kinds entry " \
                              "declares. A base class mapped to a kind that does not exist " \
                              "classifies nothing and hides a typo."

    attr_reader :kinds, :matrix, :base_classes, :sisters, :schedulers

    def initialize(kinds:, matrix:, base_classes: {}, sisters: [], schedulers: [])
      @kinds = typed_hash(kinds, String, Array)
      @matrix = typed_hash(matrix, String, Array)
      @base_classes = typed_hash(base_classes, String, Array)
      @sisters = typed_array(sisters, Array)
      # **Which kinds may hand work to a queue.** Its own row rather than a matrix edge,
      # because scheduling an entry point is not the same act as calling one: nothing may
      # reach through a doorbell, and every application still has to defer work.
      @schedulers = typed_array(schedulers, String)

      assert_globs_are_strings
      refuse_rows_naming_a_sister
      refuse_rows_naming_an_undeclared_kind
      refuse_base_classes_for_an_undeclared_kind
    end

    # The kinds a kind may never call. Every kind is its own sister — that is the whole of
    # "no kind calls its own kind" — and a declared group adds the rest. A legacy command
    # is a command that wraps something old, so calling one from a command is a write
    # sequencing a write, which is a workflow that never said so.
    def sisters_of(kind)
      group = sisters.find { |names| names.include?(kind) } || []

      ([kind] + group).uniq
    end

    # Which kind a superclass names, or nil. The superclass decides the kind; the paths
    # only decide which trees are governed, which is why two kinds may share a glob.
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
        schedulers: cop_config.fetch("Schedules", []),
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
