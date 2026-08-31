# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/inheritance"

module Shipshape
  module Measures
    # Classes under `app/` that inherit from nothing.
    class ClassesWithNoBaseClass
      TITLE = "Classes that inherit from nothing"
      LAW = "the-call-graph-is-declared"
      WHY = "Nothing says what these are, so no rule can reach them and no reader can tell " \
            "what they may do."
      CAVEAT = "Base classes are excluded — a class something else in this repository " \
               "inherits from is the answer to this measure, not an instance of it. " \
               "A class reopened rather than defined — `class String` in a core extension — " \
               "has no superclass in the file and is counted here too. The line shown under " \
               "each makes those quick to skip; a list of core class names would be a copy " \
               "of somebody else's facts, and it would rot."
      NOUN = "classes"
      SHOW_SOURCE = false

      def call(sources)
        bases = Inheritance.bases(sources)

        sources.flat_map do |source|
          candidates(source, bases).map do |node|
            Finding.new(relative: source.relative, line: node.loc.line, label: label_for(source, node))
          end
        end
      end

      def population(sources)
        sources.sum { |source| standalone(source).length }
      end

      private

      # A base class is not a stray object, and which classes are bases is derived: a class is
      # one if something else here inherits from it. A list would be a copy of a fact.
      def candidates(source, bases)
        standalone(source).reject do |node|
          ClassReading.superclass_of(node) || bases.include?(ClassReading.name_of(node).split("::").last)
        end
      end

      # A nested class is its outer class's business: counting them showed five strays for one.
      def standalone(source)
        ClassReading.classes(source).reject { |node| ClassReading.owned_by_a_class?(source.ast, node) }
      end

      def label_for(source, node)
        qualified = ClassReading.qualified_name(source.ast, node)

        qualified == ClassReading.name_of(node) ? "" : qualified
      end
    end
  end
end
