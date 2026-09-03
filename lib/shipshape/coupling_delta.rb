# frozen_string_literal: true

require "set"
require "shipshape/coupling"
require "shipshape/typed_arguments"

module Shipshape
  # Splits a coupling delta into stable/arrived/left. Holds `the-call-graph-is-declared`.
  class CouplingDelta
    include TypedArguments

    Totals = Struct.new(:was, :now, :arrived_edges, :arrived_files, :left_edges, :left_files, keyword_init: true)

    # `renames`: base path => its name at head. Defaults to `{}`, the old path-literal behaviour.
    def initialize(base:, head:, renames: {})
      @base = typed(base, Coupling::Report)
      @head = typed(head, Coupling::Report)
      @renames = typed_hash(renames, String, String)
    end

    def call
      Totals.new(
        was: based.edges.count { |edge| stable?(edge, other: head.governed) },
        now: head.edges.count { |edge| stable?(edge, other: based.governed) },
        arrived_edges: head.edges.count { |edge| !stable?(edge, other: based.governed) },
        arrived_files: (head.governed - based.governed).size,
        left_edges: based.edges.count { |edge| !stable?(edge, other: head.governed) },
        left_files: (based.governed - head.governed).size,
      )
    end

    private

    attr_reader :base, :head, :renames

    def based
      @based ||= Coupling::Report.new(
        edges: base.edges.map { |edge| Coupling::Edge.new(caller: canonical(edge.caller), callee: edge.callee && canonical(edge.callee)) },
        governed: base.governed.map { |path| canonical(path) }.to_set,
      )
    end

    def canonical(path)
      renames.fetch(path, path)
    end

    def stable?(edge, other:)
      other.include?(edge.caller) && (edge.callee.nil? || other.include?(edge.callee))
    end
  end
end
