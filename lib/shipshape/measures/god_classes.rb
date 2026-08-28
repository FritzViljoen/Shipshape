# frozen_string_literal: true

require "set"
require "shipshape/measures/finding"

module Shipshape
  module Measures
    # God classes, by Lanza and Marinescu's detection strategy: **high complexity, high
    # access to foreign data, and low cohesion, together** (*Object-Oriented Metrics in
    # Practice*, 2006). Their thresholds, from 45 Java projects: WMC >= 47, TCC < 1/3,
    # ATFD > 5.
    #
    # **Cohesion is the defining term, not size.** A long class that does one thing is long;
    # a class whose methods share no state is several classes sharing a name. Khomh et al.
    # measured the consequence — classes with antipatterns are more change- and
    # fault-prone, and **size alone cannot explain the difference** (ESE 2012).
    #
    # WHAT IS APPROXIMATED, and it is one of the three: **ATFD is a proxy here.** Measuring
    # access to foreign data properly needs type information Ruby does not give a reader, so
    # this counts the distinct external constants a class sends messages to. That is close
    # in spirit — reaching into other things — and it is not the same measure. The other two
    # are computed as defined.
    class GodClasses
      TITLE = "God classes"
      LAW = "persistence-holds-no-behaviour"
      WHY = "High complexity, reaching into many other classes, and methods that share no " \
            "state — several classes wearing one name."
      CAVEAT = "ATFD is approximated by counting external constants, because measuring " \
               "foreign data access properly needs types Ruby does not offer. WMC and TCC " \
               "are as defined (Lanza & Marinescu, 2006)."

      NOUN = "classes"

      def population(sources)
        sources.sum { |source| ClassReading.classes(source).length }
      end

      WMC = 47
      TCC = 1.0 / 3
      ATFD = 5

      BRANCHES = %i[if while until case case_match when rescue and or].freeze

      def call(sources)
        sources.flat_map do |source|
          ClassReading.classes(source).map { |node| finding(source, node) }.compact
        end
      end

      private

      def finding(source, node)
        methods = ClassReading.public_methods_of(node) + private_methods_of(node)
        return nil if methods.length < 2

        complexity = methods.sum { |method| weight(method) }
        cohesion = tight_class_cohesion(methods)
        foreign = foreign_constants(node).length
        return nil unless complexity >= WMC && cohesion < TCC && foreign > ATFD

        Finding.new(
          relative: source.relative,
          line: node.loc.line,
          label: format("%<name>s — WMC %<wmc>d, TCC %<tcc>.2f, reaches %<atfd>d other classes",
                        name: ClassReading.name_of(node), wmc: complexity, tcc: cohesion, atfd: foreign),
        )
      end

      # Cyclomatic complexity: one, plus a branch for every decision.
      def weight(method)
        count = 1
        ClassReading.walk(method.body) { |node| count += 1 if BRANCHES.include?(node.type) }
        count
      end

      # The share of method pairs that touch at least one instance variable in common. Two
      # methods that share no state are two methods that happen to live together.
      def tight_class_cohesion(methods)
        state = methods.map { |method| instance_variables_in(method) }
        pairs = state.combination(2).to_a
        return 1.0 if pairs.empty?

        connected = pairs.count { |left, right| (left & right).any? }
        connected.to_f / pairs.length
      end

      def instance_variables_in(method)
        found = Set.new
        ClassReading.walk(method.body) do |node|
          found << node.children.first if %i[ivar ivasgn].include?(node.type)
        end
        found
      end

      # The proxy for ATFD. The class's own name is excluded — naming yourself is not
      # reaching into somebody else.
      def foreign_constants(class_node)
        own = ClassReading.name_of(class_node)
        found = Set.new

        ClassReading.walk(class_node.body) do |node|
          next unless node.send_type? && node.receiver && node.receiver.const_type?

          name = node.receiver.source
          found << name unless name == own
        end
        found
      end

      def private_methods_of(class_node)
        body = class_node.body
        return [] if body.nil?

        statements = body.begin_type? ? body.children : [body]
        defs = statements.select { |node| node.is_a?(RuboCop::AST::Node) && node.def_type? }
        defs - ClassReading.public_methods_of(class_node)
      end
    end
  end
end
