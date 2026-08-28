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

    Row = Struct.new(:title, :law, :why, :caveat, :findings, :proposal, :population, :noun,
                     :unit, :exemplars, keyword_init: true) do
      def count
        findings.length
      end

      def files
        findings.map(&:relative).uniq.length
      end

      # The share that is already right. A report with no denominator is an accusation; one
      # that says four in five of your actions are already dispatch is a measurement, and it
      # is the sentence that makes the other fifth believable.
      #
      # SUBTRACT UNITS, NOT FINDINGS. Some measures find one thing per class and some find
      # many sites across a file — 186 sites in 45 controllers is not −141 clean controllers,
      # which is what this said before anybody looked at the arithmetic.
      def clean
        return nil if population.nil? || population.zero?

        population - affected
      end

      def affected
        unit == :file ? files : count
      end

      def share
        return nil if clean.nil?

        (clean * 100.0 / population).round
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
        findings = instance.call(sources)

        Row.new(
          title: measure::TITLE,
          law: measure::LAW,
          why: measure::WHY,
          caveat: measure.const_defined?(:CAVEAT) ? measure::CAVEAT : nil,
          findings: findings,
          proposal: proposal_from(instance, findings),
          population: ask(instance, :population, sources),
          noun: instance.class.const_defined?(:NOUN) ? instance.class::NOUN : nil,
          unit: instance.class.const_defined?(:UNIT) ? instance.class::UNIT : :finding,
          exemplars: ask(instance, :exemplars, sources) || [],
        )
      end
    end

    def ask(instance, message, sources)
      instance.respond_to?(message) ? instance.public_send(message, sources) : nil
    end

    # A measure proposes a better shape only where it can name one from the reader's own
    # code. Most cannot, and a generic sketch would be a slide rather than a suggestion.
    def proposal_from(instance, findings)
      return nil if findings.empty? || !instance.respond_to?(:proposal)

      instance.proposal(findings)
    end

    # One measure reads the schema rather than the code and so needs the root. Asked for by
    # arity rather than by name, because a list of which measures are special is a second
    # copy of a fact the constructor already states.
    def build(measure)
      measure.instance_method(:initialize).arity.zero? ? measure.new : measure.new(root: root)
    end
  end
end
