# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `an-operation-declares-its-permission`.
      #
      # A command or query names the permission it needs, in the file, in one greppable line.
      #
      # **Not a base class.** One that checks before dispatching to `call` is a lifecycle
      # callback wearing our name: the caller reads one method and gets two, in an order
      # nothing states, with the refusal attributed to the operation rather than the check.
      #
      # **Not the class name.** `SettleInvoice` → `:settle_invoice` is a private convention
      # with a corpus of one repository, and it changes silently under a rename — the one
      # moment a permission must not change silently.
      #
      # WHAT IT DOES NOT CATCH: it checks the declaration **exists**, never that the
      # permission named is the right one, and never that `call` consults it. A `PERMISSION`
      # on a class that never reads it passes. It cannot see a permission model at all.
      # Whether the operation is sized to exactly one permission is the judgement in
      # `one-operation-one-class`, and no check makes it.
      #
      # @example
      #   # bad — nothing here says who may do this, so nobody can tell by reading
      #   class SettleInvoice < Command
      #     def call
      #       success(InvoiceRecord.find(@invoice_id).settle!)
      #     end
      #   end
      #
      #   # good
      #   class SettleInvoice < Command
      #     PERMISSION = :settle_invoice
      #
      #     def call
      #       return failure(:forbidden) unless @actor.may?(PERMISSION)
      #
      #       success(InvoiceRecord.find(@invoice_id).settle!)
      #     end
      #   end
      class OperationDeclaresPermission < Base
        include ReadsKinds

        def on_class(node)
          return unless one_of?(governed_kinds)
          return if nested_in_a_class?(node)
          return if declares_permission?(node)

          add_offense(node.identifier, message: message_for(node.identifier.source))
        end

        private

        def declares_permission?(node)
          return false unless node.body

          node.body.each_node(:casgn).any? { |assignment| assignment.children[1].to_s == constant_name }
        end

        # A part nested inside its operation — `SettleInvoice::Line` — is not a second
        # operation, and it is reached only through the one that declared the permission.
        def nested_in_a_class?(node)
          node.each_ancestor(:class).any?
        end

        def message_for(name)
          explain(
            "`#{name}` does not say who may run it.",
            because: "Permission is a decision, so it belongs here and not in the " \
                     "controller, which places answers rather than making them. Declared " \
                     "in the file it is greppable, survives a rename, and cannot be " \
                     "forgotten — a permission derived from the class name changes " \
                     "silently the moment the class is renamed, which is exactly when it " \
                     "must not.",
            instead: <<~RUBY,
              class SettleInvoice < Command
                #{constant_name} = :settle_invoice

                def initialize(actor:, invoice_id:)
                  @actor = typed(actor, Actor)          # never `current_user`: ambient
                  @invoice_id = typed(invoice_id, Integer)
                end

                def call
                  # a named permission, one question and one answer. Asking the actor's
                  # *role* would put the permission model in every call site instead.
                  return failure(:forbidden) unless @actor.may?(#{constant_name})

                  success(InvoiceRecord.find(@invoice_id).settle!)
                end
              end

              # refusal is a value, so the action branches on it like any other outcome
              if result.success?
                redirect_to invoice_path(result.value)
              else
                render :show, status: :forbidden
              end
            RUBY
          )
        end

        def constant_name
          cop_config.fetch("ConstantName", "PERMISSION")
        end

        # Workflows are out by default: a workflow sequences operations that each declare
        # their own, and requiring one here would state a fact twice.
        def governed_kinds
          cop_config.fetch("Kinds", %w[command query io_command io_query])
        end
      end
    end
  end
end
