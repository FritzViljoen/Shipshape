# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/naming"

module Shipshape
  module Measures
    # Asking an object a question and branching on the answer.
    #
    # `if order.paid?` is the caller taking a decision that belonged to the thing it asked.
    # The rule now has two owners, and they will disagree — one of them silently, because
    # nobody greps a caller for the rule they are looking for.
    #
    # This is the most common shape in a legacy Rails application and the one that explains
    # why extracting a service so often fails to help: the logic was never in the method,
    # it was in the conditional around the call.
    #
    # **Counted anywhere**, not only in controllers. A command asking a record a question
    # and branching is the same defect, and is often where the rule actually belongs.
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

      # The framework's own objects. `request.xhr?` and `params[:format]` are properties of
      # the call being served, not an object the caller was handed — asking them is
      # placement, which is request handling's actual job.
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

        # `@order` is not a name a class can carry, and `Paid@order.call(@order: @order)`
        # is what came out before anybody read the generated line. The sigil is Ruby
        # punctuation; the word under it is the subject.
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

      # A message sent to an object the caller was handed — not to a class, not to itself,
      # and not to something reached through a class.
      #
      # THE ROOT OF THE CHAIN IS WHAT MATTERS. `Rails.env.development?` has a send as its
      # receiver, so a check on the immediate receiver let every configuration read in the
      # application through; the root is `Rails`, a constant, and that is a class method
      # call rather than an interrogation. `User.exists?` is the same and belongs to another
      # measure.
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
