# frozen_string_literal: true

require "set"
require "shipshape/sources"
require "shipshape/measures"
require "shipshape/typed_arguments"

module Shipshape
  # The introspection report: a repository that knows nothing about shipshape, answered in counts
  # and examples. Configuration-free, because a tool you must configure first goes unrun.
  class Report
    include TypedArguments

    EXAMPLES = 5

    Row = Struct.new(:title, :citation, :why, :caveat, :findings, :proposal, :population, :noun,
                     :unit, :exemplars, :headline, :units, :source, :subject, :subjects,
                     keyword_init: true) do
      # A measure recognising none of what it reads answers about the layout, not the code: iggo
      # keeps records in `app/records/`, so this read "7 of 7 controllers (100%)" against 42.
      def unmeasured?
        !subjects.nil? && subjects.zero?
      end
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
        return nil if unmeasured? || clean.nil?

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
          citation: measure::LAW,
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
          subject: measure.const_defined?(:SUBJECT) ? measure::SUBJECT : nil,
          subjects: ask(instance, :subjects, sources),
        )
      end
    end

    # Worst first: in directory order the first examples sample the file system, not the problem.
    # A measure that has ranked its own is left alone — file frequency undid the branch count.
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
