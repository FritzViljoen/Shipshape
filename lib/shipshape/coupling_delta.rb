# frozen_string_literal: true

require "shipshape/coupling"
require "shipshape/typed_arguments"

module Shipshape
  # Splits a coupling delta into stable/arrived/left. Holds `the-call-graph-is-declared`.
  class CouplingDelta
    include TypedArguments

    Totals = Struct.new(:was, :now, :arrived_edges, :arrived_files, :left_edges, :left_files, keyword_init: true)

    def initialize(base:, head:)
      @base = typed(base, Coupling::Report)
      @head = typed(head, Coupling::Report)
    end

    def call
      Totals.new(
        was: base.edges.count { |edge| stable?(edge, other: head.governed) },
        now: head.edges.count { |edge| stable?(edge, other: base.governed) },
        arrived_edges: head.edges.count { |edge| !stable?(edge, other: base.governed) },
        arrived_files: (head.governed - base.governed).size,
        left_edges: base.edges.count { |edge| !stable?(edge, other: head.governed) },
        left_files: (base.governed - head.governed).size,
      )
    end

    private

    attr_reader :base, :head

    def stable?(edge, other:)
      other.include?(edge.caller) && (edge.callee.nil? || other.include?(edge.callee))
    end
  end
end
