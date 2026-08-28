# frozen_string_literal: true

require "set"
require "shipshape/sources"
require "shipshape/measures"
require "shipshape/typed_arguments"

module Shipshape
  # The introspection report. Reads a repository that knows nothing about shipshape and
  # answers with counts and examples — one row per measure, each naming the law it points
  # at and what that measure cannot see.
  #
  # It is deliberately **read-only and configuration-free**. The first thing anybody wants
  # is a number, and a tool that must be configured before it will say anything is a tool
  # that goes unrun.
  class Report
    include TypedArguments

    EXAMPLES = 5

    Row = Struct.new(:title, :law, :why, :caveat, :findings, keyword_init: true) do
      def count
        findings.length
      end

      def files
        findings.map(&:relative).uniq.length
      end
    end

    def initialize(root:, examples: EXAMPLES)
      @root = typed(root, String)
      @examples = typed(examples, Integer)
    end

    def call
      sources = Sources.new(root: root).call

      { root: root, files: sources.length, rows: rows_for(sources) }
    end

    private

    attr_reader :root, :examples

    def rows_for(sources)
      Measures::ALL.map do |measure|
        instance = build(measure)

        Row.new(
          title: measure::TITLE,
          law: measure::LAW,
          why: measure::WHY,
          caveat: measure.const_defined?(:CAVEAT) ? measure::CAVEAT : nil,
          findings: instance.call(sources),
        )
      end
    end

    # One measure reads the schema rather than the code and so needs the root. Asked for by
    # arity rather than by name, because a list of which measures are special is a second
    # copy of a fact the constructor already states.
    def build(measure)
      measure.instance_method(:initialize).arity.zero? ? measure.new : measure.new(root: root)
    end
  end
end
