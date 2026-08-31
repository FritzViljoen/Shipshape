# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/inheritance"

module Shipshape
  module Measures
    # Classes whose parent is itself a subclass.
    class InheritanceDeeperThanOneLevel
      TITLE = "Inheritance deeper than one level"
      LAW = "an-operation-is-a-leaf"
      WHY = "An intermediate base class is where shared behaviour accretes — the god object " \
            "arriving through inheritance rather than through columns, and reachable by " \
            "everything below it."
      CAVEAT = "**Nothing enforces this.** `Shipshape/OperationsAreLeaves` refuses a second " \
               "level only in shipshape's own hierarchy — a class whose parent inherits a " \
               "base class the installer wrote — because a depth rule over somebody else's " \
               "hierarchy is a rule nobody agreed to. Everything counted here is therefore " \
               "a smell, reported and not guarded, and it will not fail a build or move " \
               "the ratchet. " \
               "A conventional application base — ApplicationRecord, ApplicationController, " \
               "ApplicationViewComponent — is excluded: Rails asks for one per framework " \
               "class, so that depth is the framework's rather than the application's. " \
               "Error hierarchies are excluded: an error taxonomy has no behaviour to " \
               "accrete, and Ruby requires the depth. Only chains this repository declares " \
               "are visible. A class inheriting from a " \
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

      # An error hierarchy is a taxonomy, not accreted behaviour, and Ruby requires the depth.
      # Counting them buried the finding: nine hundred, most of them one error file.
      EXCEPTIONS = /(Error|Exception)\z/.freeze

      def exception?(name, chains)
        seen = []
        current = name

        while current && !seen.include?(current)
          return true if EXCEPTIONS.match?(current.split("::").last)

          seen << current
          current = chains[current.split("::").last] || chains[current]
        end
        false
      end

      # The depth is the framework's: Rails asks for one of these per framework class.
      FRAMEWORK_BASE = /\AApplication[A-Z]/.freeze

      def finding(source, node, chains)
        parent = ClassReading.superclass_of(node)
        return nil if parent.nil?

        grandparent = chains[parent] || chains[parent.split("::").last]
        return nil if grandparent.nil?

        # A name collision is not a chain: keyed by simple name, `Gateways::Response <
        # Mercator::Response` looks its parent up and finds itself.
        return nil if grandparent == parent || grandparent == ClassReading.name_of(node)
        return nil if exception?(ClassReading.name_of(node), chains) || exception?(parent, chains)
        return nil if FRAMEWORK_BASE.match?(parent.split("::").last)

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
