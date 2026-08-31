# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the call site's half of `an-operation-is-a-leaf`, and does not rely on `private`
      # to do it: `private_class_method :new` is undone by `send`. This reads the call site,
      # resolves the constant, and refuses any message an operation does not answer.
      class OnlyTheDoorIsCalled < Base
        include ReadsKinds

        def on_send(node)
          receiver = node.receiver
          return unless receiver&.const_type?

          name = receiver.source.sub(/\A::/, "")
          kind = kinds.for_constant(name)
          return unless governed_kinds.include?(kind)
          return add_offense(node, message: deferred_step(name)) if deferred_inside_a_sequence?(node)
          return if allowed_for(kind).include?(node.method_name.to_s)
          return if refers_to_itself?(name)

          add_offense(node, message: message_for(name, node.method_name))
        end

        private

        # `call_later` inside a workflow lets step three start before step two has happened.
        def deferred_inside_a_sequence?(node)
          deferring.include?(node.method_name.to_s) && one_of?(sequencing_kinds)
        end

        def sequencing_kinds
          cop_config.fetch("SequencingKinds", %w[workflow])
        end

        def deferred_step(name)
          explain(
            "`#{name}.call_later` defers a step of a sequence.",
            because: "A workflow states an order, and a deferred step leaves that order: it " \
                     "is enqueued, the workflow carries on, and step three may run before " \
                     "step two has happened. The workflow then answers success for work that " \
                     "has not been done, and a step that depended on the deferred one reads a " \
                     "state that is not there yet. A sequence runs its steps.",
            instead: SYNCHRONOUS,
          )
        end

        SYNCHRONOUS = <<~RUBY
          # every step runs, in the order written, before the workflow answers
          class SettleMonth < Workflow
            def call
              settled = SettleInvoice.call(actor: actor, invoice_id: @id)
              return settled if settled.failure?

              NotifyCustomer.call(actor: actor, invoice_id: @id)
            end
          end

          # work that genuinely belongs on a queue is deferred by the operation that owns it,
          # or at the edge — never by the sequence, which would be stating an order it does
          # not keep
        RUBY

        # A class naming itself is not a call site reaching in.
        def refers_to_itself?(name)
          resolved = kinds.file_for_constant(name)

          !resolved.nil? && resolved == processed_source.file_path
        end

        def message_for(name, message)
          explain(
            "`#{name}.#{message}` is not the door. An operation answers `#{door}`.",
            because: "The door is where the permission check runs, the transaction opens " \
                     "and the return type is asserted, so a message that goes around it " \
                     "goes around all three. Everything else stopping this is a convention " \
                     "Ruby will step over — `private` is not a wall, and `send` undoes " \
                     "`private_class_method`. This reads the call site instead, so it holds " \
                     "whatever the visibility says.",
            instead: <<~RUBY,
              SettleInvoice.call(actor: actor, invoice_id: 1)

              # needed a different starting point? That is a different operation, with its
              # own name and its own door — not a second entrance to this one.
              class SettleInvoiceFromParams < Command
                private

                def call
                  SettleInvoice.call(actor: actor, invoice_id: @invoice_id)
                end
              end
            RUBY
          )
        end

        # `permissions` went with `permits?`: it keeps the branch in a longer spelling, and one
        # that disagrees with the door for an anonymous operation. Per kind, because `call_later`
        # exists only on the writing doors — allowing it everywhere raised at runtime instead.
        def allowed_for(kind)
          return allowed + deferring if deferrable_kinds.include?(kind)

          allowed
        end

        def allowed
          # Keep in step with `config/default.yml`: they drifted once, and `CopRunner` builds a
          # bare config, so the cop's own test asserted the rule the shipped config had removed.
          @allowed ||= cop_config.fetch("AllowedMessages", %w[call permission anonymous?])
        end

        def deferring
          @deferring ||= cop_config.fetch("DeferredMessages", %w[call_later])
        end

        def deferrable_kinds
          cop_config.fetch("DeferrableKinds", %w[command io_command legacy_command])
        end

        def door
          allowed.first
        end

        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow command query io_command io_query legacy_command legacy_query],
          )
        end
      end
    end
  end
end
