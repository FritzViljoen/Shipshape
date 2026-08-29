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
      # **The declared list is checked against the code**, not trusted. A hand-maintained
      # list of permissions is a copy of a fact the steps already state, and it rots in the
      # direction that grants rather than refuses: the step somebody added is the one missing
      # from the list. So the guard derives the set from what `call` actually calls, and
      # where the two disagree the list is wrong.
      #
      # WHAT IT DOES NOT CATCH: it reads constants the body **names syntactically**, and it
      # reads `STEPS` only when it is an array literal in this class's own body — a list
      # built any other way is not read, and the workflow is reported as declaring nothing. A step
      # reached through a variable, one whose constant does not resolve to a file, or an
      # operation called by another operation a level down is invisible — the derived set is
      # a floor, not a ceiling. It does not check that `call` consults `PERMISSIONS`, only
      # that the set is right, and it cannot tell whether the check happens before the first
      # step or after the third.
      #
      # @example
      #   # bad — a step was added and the list was not
      #   class SettleMonth < Workflow
      #     STEPS = [SettleInvoice].freeze
      #
      #     def call
      #       SettleInvoice.call(actor: @actor)
      #       NotifyCustomer.call(actor: @actor)
      #     end
      #   end
      #
      #   # good — the base class refuses every step's permission before the first runs
      #   class SettleMonth < Workflow
      #     STEPS = [SettleInvoice, NotifyCustomer].freeze
      #
      #     def call
      #       SettleInvoice.call(actor: @actor)
      #       NotifyCustomer.call(actor: @actor)
      #     end
      #   end
      class WorkflowAggregatesPermissions < Base
        include ReadsKinds

        def on_class(node)
          return unless one_of?(governed_kinds)
          return if node.each_ancestor(:class).any?

          declared = declared_permissions(node)
          derived = derived_permissions(node)

          return add_offense(node.identifier, message: undeclared(node.identifier.source, derived)) if declared.nil?

          missing = derived - declared
          surplus = declared - derived
          return if missing.empty? && surplus.empty?

          add_offense(constant_node(node), message: mismatched(missing, surplus))
        end

        private

        # `STEPS = [SettleInvoice, NotifyCustomer].freeze` — the operations, in the order
        # they run. nil when nothing was declared at all, which is a different mistake from
        # declaring the wrong set.
        def declared_permissions(node)
          assignment = constant_node(node)
          return unless assignment

          array = unwrap(assignment.children[2])
          return [] unless array

          # The element itself, never its namespace segments: `Billing::SettleInvoice`
          # names one step, and collecting descendants also yielded `Billing` as surplus.
          array.values.select(&:const_type?).map { |const| const.source.sub(/\A::/, "") }.uniq
        end

        # Only this class's own body. A `STEPS` on a nested class used to satisfy the outer
        # workflow, which then ran with the base class's empty list and refused nobody —
        # the cop reporting green over the exact defect it exists to prevent.
        # `STEPS = [...].freeze` is a send wrapping the array, not the array.
        def unwrap(value)
          return unless value.respond_to?(:type)

          value = value.receiver if value.send_type? && value.method_name == :freeze

          value if value.respond_to?(:array_type?) && value.array_type?
        end

        def constant_node(node)
          return unless node.body

          statements = node.body.begin_type? ? node.body.children : [node.body]

          statements.find { |statement| statement.casgn_type? && statement.children[1].to_s == list_constant }
        end

        # Every operation the body calls, resolved through the layout so a constant that
        # names no governed file is skipped rather than guessed at.
        def derived_permissions(node)
          body = node.body
          return [] unless body

          body.each_node(:send).filter_map do |send|
            receiver = send.receiver
            next unless receiver&.const_type?

            name = receiver.source.sub(/\A::/, "")
            next unless operation?(name)

            name
          end.uniq
        end

        def operation?(name)
          step_kinds.include?(kinds.for_constant(name))
        end

        def undeclared(name, derived)
          explain(
            "`#{name}` is a workflow and does not name its steps.",
            because: "A workflow spans several transactions, so a refusal partway cannot " \
                     "undo what came before — those transactions closed. Discovering at " \
                     "step three that the actor may not run step three leaves steps one " \
                     "and two done and visible, with no rollback. Before the first step is " \
                     "the only moment refusing is free.",
            instead: example(derived),
          )
        end

        def mismatched(missing, surplus)
          trouble = []
          trouble << "missing #{missing.map { |name| "`#{name}`" }.join(', ')}" if missing.any?
          trouble << "names #{surplus.map { |name| "`#{name}`" }.join(', ')}, which it does not call" if surplus.any?

          explain(
            "`#{list_constant}` disagrees with what this workflow calls: #{trouble.join('; ')}.",
            because: "The list is a second copy of a fact the steps already state, so it " \
                     "rots — and it rots in the direction that grants rather than refuses, " \
                     "because the step somebody added is the one missing from the list. " \
                     "Where the declared set and the called set disagree, the list is wrong.",
            instead: example(missing.any? ? missing : []),
          )
        end

        def example(steps)
          named = steps.any? ? steps : %w[SettleInvoice NotifyCustomer]
          entries = named.join(", ")

          <<~RUBY
            class SettleMonth < Workflow
              #{list_constant} = [#{entries}].freeze

              # the base class checks every step's permission before the first one runs,
              # because after it there is nothing left to refuse
              def call
                settled = SettleInvoice.call(actor: @actor, invoice_id: @id)
                return settled if settled.failure?

                NotifyCustomer.call(actor: @actor, invoice_id: @id)
              end
            end
          RUBY
        end

        def list_constant
          cop_config.fetch("ListConstantName", "STEPS")
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
