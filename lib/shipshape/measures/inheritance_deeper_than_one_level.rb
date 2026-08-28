# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/inheritance"

module Shipshape
  module Measures
    # Classes whose parent is itself a subclass.
    #
    # Ruby has single inheritance, so "inheriting from more than one" means depth: a chain
    # of three or more, where a class inherits from something that inherits from something.
    #
    # **An intermediate base class is where shared behaviour accretes.** It is the god object
    # arriving through inheritance rather than through columns — invisible to a column count,
    # invisible to a method count on any one class, and reachable by everything below it. A
    # reader who wants to know what a class does now has three files to read, and the middle
    # one belongs to nobody.
    #
    # One level is enough to say what a class **is**. More than one is somebody keeping a
    # place to put things.
    class InheritanceDeeperThanOneLevel
      TITLE = "Inheritance deeper than one level"
      LAW = "the-call-graph-is-declared"
      WHY = "An intermediate base class is where shared behaviour accretes — the god object " \
            "arriving through inheritance rather than through columns, and reachable by " \
            "everything below it."
      CAVEAT = "Only chains this repository declares are visible. A class inheriting from a " \
               "framework or gem class that is itself deep — most controllers, every record " \
               "— is one level as far as this can see, which is the honest limit rather " \
               "than a judgement that those are fine."
      NOUN = "classes"
      SHOW_SOURCE = false

      def call(sources)
        chains = Inheritance.map(sources)

        sources.flat_map do |source|
          ClassReading.classes(source).map { |node| finding(source, node, chains) }.compact
        end
      end

      def population(sources)
        Inheritance.map(sources).length
      end

      private

      def finding(source, node, chains)
        parent = ClassReading.superclass_of(node)
        return nil if parent.nil?

        grandparent = chains[parent.split("::").last] || chains[parent]
        return nil if grandparent.nil?

        Finding.new(
          relative: source.relative,
          line: node.loc.line,
          label: "#{ClassReading.name_of(node)} < #{parent} < #{grandparent}",
          context: { depth: 3 },
        )
      end
    end
  end
end
