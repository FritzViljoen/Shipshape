# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-permission-is-the-class-name`.
      #
      # An operation demands its own permission and every permission it reaches, read out of the
      # syntax tree of `call`. **So what it reaches has to be readable from `call`**, or the
      # aggregate is short — and a short aggregate is a fail-open: the door demands less than the
      # work performs, and the refusal arrives partway instead of at the door.
      #
      # It is short at the endpoint too. `CallGraph.routes` prints what a route demands by
      # walking the same trees, so a call site this cannot read makes that number wrong for
      # every route above it.
      #
      # Three shapes, and the first is the only one specific to workflows:
      #
      # - a **workflow** whose `call` names no operation, which sequences nothing and so
      #   aggregates nothing
      # - a `call`/`call_later` receiver that is not a constant, which nothing can resolve
      # - an operation called from a method other than the one the base class reads
      #
      # WHAT IT DOES NOT CATCH: it reads constants syntactically, so a step reached through
      # `const_get` or `send` is invisible here and to the base class alike. It does not check
      # that a named constant is called rather than merely mentioned, nor the order, nor whether
      # the actor is threaded through.
      #
      # @example
      #   # bad — a workflow that sequences nothing refuses nobody
      #   class SettleMonth < Workflow
      #     def call
      #       success(:done)
      #     end
      #   end
      #
      #   # bad — the query is reached from a helper, so the command demands nothing for it
      #   class CancelBooking < Command
      #     def call
      #       booking = load
      #       ...
      #     end
      #
      #     private
      #
      #     def load
      #       FindBooking.call(actor: actor, id: @id)
      #     end
      #   end
      #
      #   # bad — nothing can say which operation this is
      #   class CancelBooking < Command
      #     def call
      #       step = FindBooking
      #       step.call(actor: actor)
      #     end
      #   end
      #
      #   # good — what it reaches is named where the aggregate is read from
      #   class CancelBooking < Command
      #     def call
      #       booking = FindBooking.call(actor: actor, id: @id)
      #       ...
      #     end
      #   end
      class AggregationIsReadable < Base
        include ReadsKinds

        # `call_later` is the same work deferred, so the permission is still owed and the edge
        # is still an edge.
        RUNS = %i[call call_later].freeze
        SEQUENCES = %i[call anonymous_call].freeze

        def on_class(node)
          return unless one_of?(governed_kinds)
          return if node.each_ancestor(:class).any?

          sequences_nothing(node)
          unreadable_receivers(node).each { |send| add_offense(send, message: not_a_constant) }
          hidden_reaches(node).each { |send| add_offense(send, message: hidden(send.receiver.source)) }
        end

        private

        # **Only a workflow.** A command that names no operation is an ordinary command; a
        # workflow that names none is not a workflow, and answering `[]` would let it run for an
        # actor holding no grants at all.
        def sequences_nothing(node)
          return unless one_of?(sequencing_kinds)
          return if operations_called(sequencing_method(node)).any?

          add_offense(node.identifier, message: names_nothing(node.identifier.source))
        end

        # An operation reached from any method other than the one the base class reads. The
        # constant must resolve to a real operation, so a helper building a shape is not swept up.
        def hidden_reaches(node)
          methods_of(node).reject { |method| SEQUENCES.include?(method.method_name) }
                          .flat_map { |method| operation_sends(method) }
        end

        # `step.call(...)`, `@steps.each { |s| s.call }` — legal Ruby that resolves to no
        # permission.
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

        # Only this class's own methods — a `call` on a class nested inside is that class's
        # business and must not answer for this one.
        def methods_of(node)
          return [] unless node.body

          statements = node.body.begin_type? ? node.body.children : [node.body]
          statements.select(&:def_type?)
        end

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
                     "workflow spans several transactions, and discovering at step three that " \
                     "the actor may not run step three leaves steps one and two done and " \
                     "visible, with no rollback. Before the first step is the only moment " \
                     "refusing is free.",
            instead: example,
          )
        end

        def hidden(name)
          explain(
            "`#{name}` is reached from somewhere the permissions are not read from.",
            because: "An operation demands what it reaches, read out of `call` and nothing " \
                     "else — so an operation reached from another method is a permission never " \
                     "demanded. The door then admits an actor the work will refuse, and the " \
                     "refusal arrives partway instead of at the door. It also makes the number " \
                     "`CallGraph.routes` prints wrong for every route above this one.",
            instead: example,
          )
        end

        def not_a_constant
          explain(
            "This receiver is not a constant, so nothing can say which operation it is.",
            because: "Permissions are read off the constants `call` names. A receiver computed " \
                     "at runtime resolves to none, so the operation demands nothing for work " \
                     "that still runs — and the build stays green, because there is nothing " \
                     "left to look at.",
            instead: example,
          )
        end

        def example
          <<~RUBY
            class SettleMonth < Workflow
              # read out of `call`, so every permission below is demanded before the first
              # line of work runs
              def call
                settled = SettleInvoice.call(actor: actor, invoice_id: @id)
                return settled if settled.failure?

                NotifyCustomer.call(actor: actor, invoice_id: @id)
              end
            end
          RUBY
        end

        def step_kinds
          cop_config.fetch("StepKinds", %w[command query io_command io_query legacy_command legacy_query])
        end

        # **Every operation aggregates, so every operation is read.** Scoping this to workflows
        # left a command reaching a query through a helper unreported, which is the same
        # fail-open one kind down.
        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query legacy_command legacy_query])
        end

        def sequencing_kinds
          cop_config.fetch("SequencingKinds", %w[workflow])
        end
      end
    end
  end
end
