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
      # The findings ARE classes, and the path names them. Printing `class Booking <
      # ApplicationRecord` under `app/models/booking.rb` is the same word twice.
      SHOW_SOURCE = false

      def call(sources)
        sources.flat_map do |source|
          standalone(source).reject { |node| ClassReading.superclass_of(node) }.map do |node|
            Finding.new(relative: source.relative, line: node.loc.line, label: label_for(source, node))
          end
        end
      end

      def population(sources)
        sources.sum { |source| standalone(source).length }
      end

      private

      # A class nested inside another class is that class's own business. Counting
      # `SiteEngine::ProductFactory::ProductCode` as an unclassified object put five entries
      # in the report for one file and stripped the namespace off every one of them, so a
      # reader saw five stray objects where there is one factory with four inner parts.
      def standalone(source)
        ClassReading.classes(source).reject { |node| ClassReading.owned_by_a_class?(source.ast, node) }
      end

      # No label where the path already says it. A namespaced class is the exception: the
      # source line reads `class ProductFactory` and says nothing about SiteEngine.
      def label_for(source, node)
        qualified = ClassReading.qualified_name(source.ast, node)

        qualified == ClassReading.name_of(node) ? "" : qualified
      end
    end
  end
end
