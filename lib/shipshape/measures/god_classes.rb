# frozen_string_literal: true

require "set"
require "shipshape/measures/finding"

module Shipshape
  module Measures
    # God classes, by Lanza and Marinescu's detection strategy: **high complexity, reaching
    # into many other classes, and low cohesion, all three together** (*Object-Oriented
    # Metrics in Practice*, 2006). Their thresholds, from 45 Java projects: weighted method
    # count >= 47, tight class cohesion < 1/3, access to foreign data > 5.
    #
    # The published names for those three are WMC, TCC and ATFD. **They do not appear in
    # the report** — an abbreviation asks every reader to have been in the room where it was
    # learned, and a report nobody can read is a report nobody acts on. They stay here,
    # where a reader is checking the implementation against the paper.
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
      CAVEAT = "Three measurements together, and a class is listed only when it exceeds all " \
               "three thresholds: how complex it is (decisions across every method), how " \
               "little its methods share state, and how many other classes it reaches into. " \
               "The third is approximated — knowing what data a class reaches for properly " \
               "needs type information Ruby does not offer — so it counts the distinct other " \
               "classes it sends messages to. The first two are computed as Lanza and " \
               "Marinescu define them (Object-Oriented Metrics in Practice, 2006), whose " \
               "thresholds these are. No ratio is reported: one god class is a bottleneck " \
               "the whole team queues behind, so a denominator would make a concentrated " \
               "harm look diffuse."

      # NO RATIO HERE, DELIBERATELY. "98% of your classes are not god classes" reassures,
      # and it is the wrong reading: one god class is a bottleneck the whole team queues
      # behind, so a denominator makes a concentrated harm look diffuse. It is the
      # "99.9% of our queries are fast" of architecture.
      #
      # What scales with the harm is CONCENTRATION — how much of the application's
      # complexity sits in these few classes — so that is what this reports instead.
      def headline(sources)
        total = complexity_of_everything(sources)
        return nil if total.zero?

        mine = call(sources).sum { |finding| finding.context[:wmc] }
        return nil if mine.zero?

        "These hold **#{(mine * 100.0 / total).round}% of the application's total complexity**."
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
          # Plain words. WMC, TCC and ATFD ask every reader to have been in the room where
          # they were learned, which is the industry-vocabulary defect one layer out — a
          # report nobody can read is a report nobody acts on.
          label: format("complexity %<wmc>d, only %<tcc>d%% of its method pairs share any " \
                        "state, reaches %<atfd>d other classes",
                        wmc: complexity, tcc: (cohesion * 100).round, atfd: foreign),
          context: { wmc: complexity },
        )
      end

      def complexity_of_everything(sources)
        sources.sum do |source|
          ClassReading.classes(source).sum do |node|
            (ClassReading.public_methods_of(node) + private_methods_of(node)).sum { |method| weight(method) }
          end
        end
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
