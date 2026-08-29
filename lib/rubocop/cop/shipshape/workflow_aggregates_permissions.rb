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
      # WHAT IT DOES NOT CATCH: it reads constants the body **names syntactically**. A step
      # reached through a variable, one whose constant does not resolve to a file, or an
      # operation called by another operation a level down is invisible — the derived set is
      # a floor, not a ceiling. It does not check that `call` consults `PERMISSIONS`, only
      # that the set is right, and it cannot tell whether the check happens before the first
      # step or after the third.
      #
      # @example
      #   # bad — a step was added and the list was not
      #   class SettleMonth < Workflow
      #     PERMISSIONS = [SettleInvoice::PERMISSION].freeze
      #
      #     def call
      #       SettleInvoice.call(...)
      #       NotifyCustomer.call(...)
      #     end
      #   end
      #
      #   # good
      #   class SettleMonth < Workflow
      #     PERMISSIONS = [SettleInvoice::PERMISSION, NotifyCustomer::PERMISSION].freeze
      #
      #     def call
      #       return failure(:forbidden) unless @actor.may_all?(PERMISSIONS)
      #       ...
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

        # `PERMISSIONS = [A::PERMISSION, B::PERMISSION].freeze` — the operation names, in
        # declaration order. nil when nothing was declared at all, which is a different
        # mistake from declaring the wrong set.
        def declared_permissions(node)
          assignment = constant_node(node)
          return unless assignment

          assignment.each_descendant(:const).filter_map do |const|
            next unless const.children[1].to_s == permission_constant

            owner_of(const)
          end.uniq
        end

        def constant_node(node)
          return unless node.body

          node.body.each_node(:casgn).find { |assignment| assignment.children[1].to_s == list_constant }
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

        # `SettleInvoice::PERMISSION` — the class the permission belongs to.
        def owner_of(const)
          owner = const.children.first
          owner&.source&.sub(/\A::/, "")
        end

        def undeclared(name, derived)
          explain(
            "`#{name}` is a workflow and does not name the permissions its steps need.",
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
          entries = named.map { |step| "#{step}::#{permission_constant}" }.join(", ")

          <<~RUBY
            class SettleMonth < Workflow
              #{list_constant} = [#{entries}].freeze

              def call
                # before the first step, because after it there is nothing to refuse
                return failure(:forbidden) unless @actor.may_all?(#{list_constant})

                settled = SettleInvoice.call(actor: @actor, invoice_id: @id)
                return settled if settled.failure?

                NotifyCustomer.call(actor: @actor, invoice_id: @id)
              end
            end
          RUBY
        end

        def list_constant
          cop_config.fetch("ListConstantName", "PERMISSIONS")
        end

        def permission_constant
          cop_config.fetch("ConstantName", "PERMISSION")
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
