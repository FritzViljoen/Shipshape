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

      BRANCHES = %i[if case case_match while until].freeze

      def call(sources)
        controllers(sources).flat_map do |source|
          ClassReading.classes(source).flat_map do |node|
            ClassReading.public_methods_of(node).flat_map { |action| branches_in(source, action) }
          end
        end
      end

      private

      def controllers(sources)
        sources.select { |source| source.relative.split("/")[1] == "controllers" }
      end

      def branches_in(source, action)
        found = []
        ClassReading.walk(action.body) do |node|
          next unless BRANCHES.include?(node.type)

          found << Finding.new(relative: source.relative, line: node.loc.line, label: "in ##{action.method_name}")
        end
        found
      end
    end
  end
end
