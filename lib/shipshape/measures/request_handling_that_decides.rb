# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Conditionals inside controller actions.
    #
    # Request handling dispatches; it does not decide. A branch in an action is a rule that
    # has escaped its home — and it is the rule nobody can find later, because nobody greps
    # a controller for business logic.
    #
    # **Guard's limit, and it is a real one:** this cannot tell a presentation branch from a
    # domain one. `return render :new if @person.errors.any?` is counted the same as a
    # pricing decision. The number is therefore an upper bound and an invitation to read,
    # not a defect count — and saying so is the difference between a report somebody trusts
    # and one they argue with.
    class RequestHandlingThatDecides
      TITLE = "Branches inside request handling"
      LAW = "no-decisions-in-request-handling"
      WHY = "A branch in an action is a rule that has escaped its home, and nobody greps a " \
            "controller for business logic."
      CAVEAT = "Counts every conditional, including presentation ones. An upper bound, and " \
               "an invitation to read rather than a defect count."

      NOUN = "actions"
      BRANCHES = %i[if case case_match while until].freeze

      def population(sources)
        controllers(sources).sum do |source|
          ClassReading.classes(source).sum { |node| ClassReading.public_methods_of(node).length }
        end
      end

      # Many branches land in one action, so the clean count is actions without any — not
      # actions minus branches, which is not a number about anything.
      def units(findings)
        findings.map { |finding| [finding.relative, finding.context[:action]] }.uniq.length
      end

      def exemplars(sources)
        controllers(sources).flat_map do |source|
          ClassReading.classes(source).flat_map do |node|
            ClassReading.public_methods_of(node).reject { |action| branches_in(source, action).any? }.map do |action|
              Finding.new(relative: source.relative, line: action.loc.line,
                          label: "##{action.method_name} decides nothing")
            end
          end
        end
      end

      # ONE LINE PER ACTION, not per branch. Fifteen hundred branch locations is a list
      # nobody reads; "#create — 23 branches" names the action to open first, and the total
      # is in the headline where it belongs.
      def call(sources)
        controllers(sources).flat_map do |source|
          ClassReading.classes(source).flat_map do |node|
            ClassReading.public_methods_of(node).map { |action| branchiest(source, action) }.compact
          end
        end.sort_by { |finding| -finding.context[:branches] }
      end

      def headline(sources)
        total = call(sources).sum { |finding| finding.context[:branches] }
        return nil if total.zero?

        "#{total} branches in all, and the ten worst actions hold " \
          "#{call(sources).first(10).sum { |finding| finding.context[:branches] }} of them."
      end

      def units(findings)
        findings.length
      end

      private

      def controllers(sources)
        sources.select { |source| source.relative.split("/")[1] == "controllers" }
      end

      def branchiest(source, action)
        found = branches_in(source, action)
        return nil if found.empty?

        Finding.new(
          relative: source.relative,
          line: action.loc.line,
          label: "##{action.method_name} — #{found.length} #{found.length == 1 ? "branch" : "branches"}",
          context: { action: action.method_name, branches: found.length },
        )
      end

      def branches_in(source, action)
        found = []
        ClassReading.walk(action.body) do |node|
          next unless BRANCHES.include?(node.type)

          found << Finding.new(relative: source.relative, line: node.loc.line,
                               label: "in ##{action.method_name}", context: { action: action.method_name })
        end
        found
      end
    end
  end
end
