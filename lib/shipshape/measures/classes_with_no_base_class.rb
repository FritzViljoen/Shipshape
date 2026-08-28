# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Classes under `app/` that inherit from nothing.
    #
    # A plain object is not a defect on its own. What it is, is **unclassifiable**: nothing
    # says whether it reads, writes, holds a shape or wraps a table, so no rule can reach it
    # and no reader can tell what it is entitled to do. Every one of these is a decision
    # nobody has made yet.
    #
    # This is usually the largest number in the report, and it is the one that explains all
    # the others.
    class ClassesWithNoBaseClass
      TITLE = "Classes that inherit from nothing"
      LAW = "the-call-graph-is-declared"
      WHY = "Nothing says what these are, so no rule can reach them and no reader can tell " \
            "what they may do."
      NOUN = "classes"

      def population(sources)
        sources.sum { |source| ClassReading.classes(source).length }
      end

      def call(sources)
        sources.flat_map do |source|
          ClassReading.classes(source).reject { |node| ClassReading.superclass_of(node) }.map do |node|
            Finding.new(relative: source.relative, line: node.loc.line, label: ClassReading.name_of(node))
          end
        end
      end
    end
  end
end
