# frozen_string_literal: true

require "set"
require "shipshape/sources"
require "shipshape/measures"
require "shipshape/typed_arguments"

module Shipshape
  # The introspection report: a repository that knows nothing about shipshape, answered in counts
  # and examples, each row naming its law and what the measure cannot see. Read-only and
  # configuration-free, because a tool that must be configured before it says anything goes unrun.
  class Report
    include TypedArguments

    EXAMPLES = 5

    Row = Struct.new(:title, :law, :why, :caveat, :findings, :proposal, :population, :noun,
                     :unit, :exemplars, :headline, :units, :source, keyword_init: true) do
      def count
        findings.length
      end

      def files
        findings.map(&:relative).uniq.length
      end

      # Subtract UNITS, not findings: 186 sites in 45 controllers is not −141 clean ones.
      def clean
        return nil if population.nil? || population.zero?

        population - affected
      end

      def source?
        source != false
      end

      def affected
        return units if units

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
          findings: ranked(findings, measure),
          proposal: proposal_from(instance, findings),
          population: ask(instance, :population, sources),
          noun: instance.class.const_defined?(:NOUN) ? instance.class::NOUN : nil,
          unit: instance.class.const_defined?(:UNIT) ? instance.class::UNIT : :finding,
          exemplars: ask(instance, :exemplars, sources) || [],
          headline: ask(instance, :headline, sources),
          units: instance.respond_to?(:units) ? instance.units(findings) : nil,
          source: measure.const_defined?(:SHOW_SOURCE) ? measure::SHOW_SOURCE : true,
        )
      end
    end

    # Worst first: findings arrive in directory order, so the first examples were a sample of the
    # file system. A measure that has ranked its own is left alone — sorting by file frequency
    # undid the branch count underneath, showing `#new — 1 branch` above `#create — 14`.
    def ranked(findings, measure)
      return findings if findings.empty? || measure.const_defined?(:SELF_RANKED)

      weight = findings.group_by(&:relative).transform_values(&:length)

      findings.sort_by { |finding| [-weight.fetch(finding.relative), finding.relative, finding.line] }
    end

    def ask(instance, message, sources)
      instance.respond_to?(message) ? instance.public_send(message, sources) : nil
    end

    def proposal_from(instance, findings)
      return nil if findings.empty? || !instance.respond_to?(:proposal)

      instance.proposal(findings)
    end

    # Asked by arity, not by name: a list of which measures are special is a second copy.
    def build(measure)
      measure.instance_method(:initialize).arity.zero? ? measure.new : measure.new(root: root)
    end
  end
end
