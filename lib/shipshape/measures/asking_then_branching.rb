# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/naming"

module Shipshape
  module Measures
    # Asking an object a question and branching on the answer.
    class AskingThenBranching
      TITLE = "Asking, then branching on the answer"
      LAW = "no-decisions-in-request-handling"
      WHY = "The caller has taken a decision that belonged to the thing it asked, so the " \
            "rule now has two owners and they will disagree."
      CAVEAT = "A nil guard and a presence check read the same way to a parser. Predicate " \
               "methods are the strong signal; the rest is an invitation to look."

      NOUN = "conditionals"
      CONDITIONS = %i[if case].freeze

      def population(sources)
        sources.sum { |source| conditions(source).length }
      end
      IGNORED = %i[nil? present? blank? empty? any? none? zero? nil].freeze

      # The call being served, not an object the caller was handed: asking is placement.
      FRAMEWORK = %i[request response params session flash cookies headers env
                     controller helpers view_context].freeze

      def call(sources)
        sources.flat_map do |source|
          conditions(source).map { |node| finding(source, node) }.compact
        end
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil? || finding.context.nil?

        # The sigil is punctuation: `Paid@order.call(@order: @order)` is what came out first.
        receiver = finding.context[:receiver]
        subject = receiver.to_s.delete_prefix("@@").delete_prefix("@")
        question = finding.context[:question]
        name = "#{Naming.camel(question.to_s.delete_suffix("?").delete_suffix("!"))}#{Naming.camel(subject)}"

        <<~TEXT
          `#{finding.relative}:#{finding.line}` asks `#{receiver}.#{question}` and decides what to
          do about the answer. The decision belongs with the thing that knows it — either
          inside `#{receiver}`, or in an operation that answers with the decision already made:

          ```ruby
          # instead of asking and branching here
          result = #{name}.call(#{subject}: #{receiver})

          return failure(result.error) unless result.success?
          ```

          A caller that may not interrogate can only know what it is told, which is why
          `tell-dont-ask` and `nothing-fails-quietly` are one exchange: one forbids the
          question, the other obliges the answer.
        TEXT
      end

      private

      def conditions(source)
        found = []
        ClassReading.walk(source.ast) do |node|
          next unless CONDITIONS.include?(node.type)

          found << node
        end
        found
      end

      def finding(source, node)
        test = node.condition
        return nil unless asking?(test)

        Finding.new(
          relative: source.relative,
          line: node.loc.line,
          label: "#{test.receiver.source}.#{test.method_name}",
          context: { receiver: test.receiver.source, question: test.method_name },
        )
      end

      # The root of the chain is what matters: `Rails.env.development?` has a send as its
      # receiver, so checking the immediate one let every configuration read through.
      def asking?(test)
        return false unless test.is_a?(RuboCop::AST::Node) && test.send_type?
        return false if test.receiver.nil?
        return false if IGNORED.include?(test.method_name)
        return false unless test.method_name.to_s.match?(/\A\w+\??\z/)

        root = root_of(test)
        return false if root.nil? || root.const_type? || root.self_type?
        return false if root.send_type? && root.receiver.nil? && FRAMEWORK.include?(root.method_name)

        test.method_name.to_s.end_with?("?") || test.arguments.empty?
      end

      def root_of(node)
        current = node
        current = current.receiver while current.respond_to?(:receiver) && current.receiver

        current
      end
    end
  end
end
