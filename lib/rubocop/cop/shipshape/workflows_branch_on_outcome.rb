# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the workflow half of `no-decisions-in-request-handling`.
      #
      # **A workflow is closer to a controller than to a command.** It sequences; it does not
      # work. It opens no transaction of its own, it writes nothing, and the only thing it is
      # entitled to know about a step is whether the step succeeded.
      #
      # So it branches on the **outcome** — `success?`, `failure?`, the error code — and never
      # on what the step answered with. `charge.value.total > 100` is a rule about totals
      # living in the coordinator, where it applies to one sequence instead of to every caller
      # of the thing that owns totals.
      #
      # **`Shipshape/NoDecisionsInRequestHandling` cannot reach this**, which is why it is a
      # second cop rather than a wider `Kinds` list. That one looks for an instance variable
      # being interrogated, because a controller's subject is `@story`; a workflow's is a
      # local holding the last step's `Result`, and adding locals to that cop would fire on
      # every controller branching on something it parsed.
      #
      # WHAT IT DOES NOT CATCH: it keys on the message `value`, so a decision made from
      # something a workflow fetched another way — a query result assigned earlier, a constant
      # — is invisible. A local that happens to answer `value` and is not a `Result` is a false
      # positive, to be argued rather than suppressed. It says nothing about a decision made
      # outside a condition, because passing a value on is the whole point of having one.
      # **Tests are exempt.**
      #
      # @example
      #   # bad — a rule about totals, living in the sequence
      #   if charge.value.total > 100
      #
      #   # good — the only thing a workflow is entitled to know
      #   return failure(charge.error) if charge.failure?
      #
      #   # good — the step decides, and says so in its code
      #   if charge.error == :over_limit
      class WorkflowsBranchOnOutcome < Base
        include ReadsKinds

        # What a `Result` answers about itself. Everything here is the outcome; `value` is the
        # work, and the work is for passing on.
        OUTCOME = %i[success? failure? error].freeze

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
            because: "A workflow is closer to a controller than to a command: it sequences, " \
                     "it opens no transaction and it writes nothing. The only thing it is " \
                     "entitled to know about a step is whether the step succeeded. A rule " \
                     "read out of the answer — a total, a status, a tier — is a rule that " \
                     "now applies to this one sequence instead of to every caller of the " \
                     "operation that owns it, and the next sequence will not have it.",
            instead: <<~RUBY,
              # the outcome is what a workflow may ask
              return failure(charge.error) if charge.failure?

              # the rule belongs to whoever owns the number, and comes back as a code
              class ChargeCard < IoCommand
                def call
                  return failure(:over_limit) if @amount_cents > LIMIT

                  success(...)
                end
              end
            RUBY
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
