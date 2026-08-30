# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # A branch over domain literals that answers with literals: a lookup table written as
    # code.
    #
    # ```ruby
    # case levy
    # when "vat"     then 0.15
    # when "tourism" then 0.01
    # end
    # ```
    #
    # **That is three facts about the business, and none of them is in the database.**
    # Changing a rate is a deploy. Adding a levy is a deploy, in a file the person who knows
    # the answer cannot read. A tenant cannot have its own. The set cannot be listed without
    # grepping, so no screen can offer it and no report can total it.
    #
    # **This is the commonest reason a service becomes soup.** Each new case is one more
    # branch in a method that already had five, and the method grows because the *data* grew
    # — which is the one kind of growth refactoring never fixes, because the code was never
    # the problem.
    #
    # The test is whether the branch encodes a **fact somebody outside the team owns**. A
    # rate, a fee, a term of art, a status the business named. Those are rows. A branch on
    # something the code itself decides — a nil check, a size comparison — is control flow
    # and belongs where it is.
    class RulesThatAreReallyData
      TITLE = "Rules that are really data"
      LAW = "no-industry-terms-in-code"
      WHY = "No industry terms in code: a word the business owns is a row, not a branch. " \
            "Held as code, a rate cannot be changed without a deploy, cannot differ per " \
            "tenant, cannot be listed on a screen, and cannot be corrected by the person " \
            "who knows the answer."
      CAVEAT = "**This cites a principle rather than a law, and nothing enforces it** — it is a judgement about what the business owns, " \
               "and no check makes it. What is counted is the shape a table takes when it " \
               "is written as code: a `case` over string or symbol literals whose branches " \
               "answer with literals. A lookup spelled as a Hash constant is already data " \
               "in the code and is not counted, though it still cannot be edited without a " \
               "deploy. A branch on a nil, a size or a boolean is control flow and is " \
               "excluded. A rate held in a constant and used once is invisible."
      NOUN = "conditionals"

      # Two is a coincidence; three is a table.
      MINIMUM_BRANCHES = 3

      def population(sources)
        sources.sum { |source| source.ast ? source.ast.each_node(:case).count : 0 }
      end

      def call(sources)
        sources.flat_map { |source| tables_in(source) }
      end

      private

      def tables_in(source)
        return [] unless source.ast

        source.ast.each_node(:case).filter_map do |node|
          next unless table?(node)

          Finding.new(relative: source.relative, line: node.loc.line,
                      label: "#{node.when_branches.length} branches over " \
                             "#{subject(node)}, each answering with a literal")
        end
      end

      # Every `when` names a literal, and every branch answers with one. Anything else is
      # control flow: the shape being counted is a table, not a decision.
      def table?(node)
        return false unless node.condition
        return false if node.when_branches.length < MINIMUM_BRANCHES

        node.when_branches.all? { |branch| named_case?(branch) && answers_with_a_literal?(branch) }
      end

      def named_case?(branch)
        branch.conditions.any? && branch.conditions.all? { |condition| %i[str sym].include?(condition.type) }
      end

      LITERAL = %i[str sym int float true false array hash].freeze

      def answers_with_a_literal?(branch)
        body = branch.body

        !body.nil? && LITERAL.include?(body.type)
      end

      def subject(node)
        node.condition.source.lines.first.to_s.strip[0, 40]
      end
    end
  end
end
