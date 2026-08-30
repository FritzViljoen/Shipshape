# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-workflow-aggregates-its-permissions`.
      #
      # A workflow spans several transactions, so a refusal partway cannot undo what came
      # before — the earlier transactions closed. The only moment refusal is free is before
      # the first step.
      #
      # **The steps are read out of `call`, so `call` has to name them.** They were a `STEPS`
      # constant for a while, and a constant beside the method that already lists them is the
      # same fact written twice; the copy rotted in the direction that grants, because the
      # step somebody added is the one missing from the list. The base class reads the syntax
      # tree of `call` instead.
      #
      # **So this cop's job is the reader's blind spots, and it fails them rather than
      # describing them.** A step the reader cannot see is a permission never demanded, and
      # the workflow runs for an actor who should have been refused — after step one has
      # committed. Three shapes are unreadable, and all three are ordinary Ruby:
      #
      # - `call` naming no operation at all, so the workflow aggregates nothing
      # - a receiver that is not a constant, so no reader can say which operation it is
      # - an operation called from another method, where the reader does not look
      #
      # The second and third are the ones worth the cop. A workflow with one visible step and
      # one hidden one is the fail-open case: the base class finds a step, raises nothing, and
      # demands half the permissions it owes.
      #
      # WHAT IT DOES NOT CATCH: it reads constants syntactically, so a step reached through
      # `const_get`, `send`, or a constant assigned from a variable is invisible here and to
      # the base class alike. It does not check that a named constant is called rather than
      # merely mentioned, nor the order of the steps, nor whether the actor is threaded
      # through to each one.
      #
      # @example
      #   # bad — sequences nothing, so it aggregates no permission and refuses nobody
      #   class SettleMonth < Workflow
      #     def call
      #       success(:done)
      #     end
      #   end
      #
      #   # bad — the step is hidden from the method that is read
      #   class SettleMonth < Workflow
      #     def call
      #       SettleInvoice.call(actor: actor)
      #       sequence
      #     end
      #
      #     private
      #
      #     def sequence
      #       NotifyCustomer.call(actor: actor)
      #     end
      #   end
      #
      #   # bad — nothing can say which operation this is
      #   class SettleMonth < Workflow
      #     def call
      #       step = SettleInvoice
      #       step.call(actor: actor)
      #     end
      #   end
      #
      #   # good — `call` names its steps, so the base class refuses them all before the first
      #   class SettleMonth < Workflow
      #     def call
      #       SettleInvoice.call(actor: actor)
      #       NotifyCustomer.call(actor: actor)
      #     end
      #   end
      class WorkflowAggregatesPermissions < Base
        include ReadsKinds

        # `call_later` is the same step deferred. The work still runs, so the permission is
        # still owed, and the base class reads both.
        RUNS = %i[call call_later].freeze
        SEQUENCES = %i[call anonymous_call].freeze

        def on_class(node)
          return unless one_of?(governed_kinds)
          return if node.each_ancestor(:class).any?

          add_offense(node.identifier, message: names_nothing(node.identifier.source)) if steps_named(node).empty?
          unreadable_receivers(node).each { |send| add_offense(send, message: not_a_constant) }
          hidden_steps(node).each { |send| add_offense(send, message: hidden(send.receiver.source)) }
        end

        private

        # Every operation `call` names, resolved through the layout so a constant that names
        # no governed file is skipped rather than guessed at.
        def steps_named(node)
          operations_called(sequencing_method(node))
        end

        # An operation called from any method that is not the one the base class reads. The
        # constant has to resolve to a real operation, so a private helper calling a shape or
        # a `Proc` is not swept up.
        def hidden_steps(node)
          methods_of(node).reject { |method| SEQUENCES.include?(method.method_name) }
                          .flat_map { |method| operation_sends(method) }
        end

        # `step.call(...)`, `@steps.each { |s| s.call }` — legal Ruby that no reader can
        # resolve to a permission.
        def unreadable_receivers(node)
          method = sequencing_method(node)
          return [] unless method

          method.each_node(:send).select do |send|
            RUNS.include?(send.method_name) && send.receiver && !send.receiver.const_type?
          end
        end

        def operation_sends(method)
          method.each_node(:send).select do |send|
            next false unless RUNS.include?(send.method_name)

            receiver = send.receiver
            receiver&.const_type? && operation?(constant_name(receiver))
          end
        end

        def operations_called(method)
          return [] unless method

          operation_sends(method).map { |send| constant_name(send.receiver) }.uniq
        end

        # Only this class's own methods — a `call` on a class nested inside the workflow is
        # that class's business, and must not satisfy the workflow.
        def methods_of(node)
          return [] unless node.body

          statements = node.body.begin_type? ? node.body.children : [node.body]
          statements.select(&:def_type?)
        end

        # `anonymous_call` is the same method for a workflow that runs before anyone is
        # identified — it sequences steps too, and it is read the same way.
        def sequencing_method(node)
          methods_of(node).find { |method| SEQUENCES.include?(method.method_name) }
        end

        # A leading `::` is part of the source but not part of the name.
        def constant_name(receiver)
          receiver.source.sub(/\A::/, "")
        end

        def operation?(name)
          step_kinds.include?(kinds.for_constant(name))
        end

        def names_nothing(name)
          explain(
            "`#{name}#call` names no operation to run.",
            because: "A workflow is a sequence, and its permissions are read out of `call` — " \
                     "so a `call` naming nothing aggregates nothing and refuses nobody. A " \
                     "workflow spans several transactions, and discovering at step three " \
                     "that the actor may not run step three leaves steps one and two done " \
                     "and visible, with no rollback. Before the first step is the only " \
                     "moment refusing is free.",
            instead: example,
          )
        end

        def hidden(name)
          explain(
            "`#{name}` is a step, and it is called from somewhere the permissions are not read from.",
            because: "The base class reads `call` and nothing else, so a step reached from " \
                     "another method is a permission never demanded — and a workflow that " \
                     "names one step and hides another passes every check, then refuses at " \
                     "the hidden one with the first step already committed. A workflow is a " \
                     "sequence; a step that does not appear in the sequence is hidden from " \
                     "the reader as well as from the reading.",
            instead: example,
          )
        end

        def not_a_constant
          explain(
            "This step's receiver is not a constant, so nothing can say which operation it is.",
            because: "Permissions are read off the constants `call` names. A receiver " \
                     "computed at runtime resolves to no permission, so the workflow demands " \
                     "nothing for a step that still runs — and the build stays green, " \
                     "because there is nothing left to look at.",
            instead: example,
          )
        end

        def example
          <<~RUBY
            class SettleMonth < Workflow
              # the base class reads these out of `call` and checks every permission before
              # the first one runs, because after it there is nothing left to refuse
              def call
                settled = SettleInvoice.call(actor: actor, invoice_id: @id)
                return settled if settled.failure?

                NotifyCustomer.call(actor: actor, invoice_id: @id)
              end
            end
          RUBY
        end

        def step_kinds
          cop_config.fetch("StepKinds", %w[command query io_command io_query])
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow])
        end
      end
    end
  end
end
