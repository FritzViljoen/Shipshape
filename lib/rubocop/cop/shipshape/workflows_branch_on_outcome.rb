# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the workflow half of `no-decisions-in-request-handling`.
      class WorkflowsBranchOnOutcome < Base
        include ReadsKinds

        # What a `Result` answers about itself. Everything here is the outcome; `value` is the
        # work, and the work is for passing on.
        OUTCOME = %i[success? failure? error].freeze

        ANSWERED = <<~RUBY
          # the outcome is what a workflow may ask
          return failure(charge.error) if charge.failure?

          # the rule belongs to whoever owns the number, and comes back as a code
          class ChargeCard < IoWrite
            def call
              return failure(:over_limit) if @amount_cents > LIMIT

              success(...)
            end
          end
        RUBY

        def on_if(node)
          return unless one_of?(governed_kinds)

          decisions_in(node.condition).each { |send| add_offense(send, message: message_for(send)) }
        end
        alias on_case on_if

        private

        def decisions_in(condition)
          return [] if condition.nil?

          found = []
          walk(condition) do |node|
            found << node if node.send_type? && node.method_name == value_message
          end
          found
        end

        def walk(node, &block)
          return unless node.respond_to?(:each_child_node)

          block.call(node)
          node.each_child_node { |child| walk(child, &block) }
        end

        def message_for(node)
          receiver = node.receiver&.source || "the step"

          explain(
            "`#{receiver}.#{node.method_name}` is what a step answered with, and a workflow " \
            "decides nothing about it.",
            because: "A workflow is closer to a controller than to a write: it sequences, " \
                     "it opens no transaction and it writes nothing. The only thing it is " \
                     "entitled to know about a step is whether the step succeeded. A rule " \
                     "read out of the answer — a total, a status, a tier — is a rule that " \
                     "now applies to this one sequence instead of to every caller of the " \
                     "operation that owns it, and the next sequence will not have it.",
            instead: ANSWERED,
          )
        end

        def value_message
          @value_message ||= cop_config.fetch("ValueMessage", "value").to_sym
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow])
        end
      end
    end
  end
end
