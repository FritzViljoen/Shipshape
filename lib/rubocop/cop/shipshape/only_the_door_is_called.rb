# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the call site's half of `an-operation-is-a-leaf`, and does not rely on `private`
      # to do it.
      #
      # **Everything else guarding the door is a convention Ruby will step over.** `private`
      # is not a wall, `private_class_method :new` is undone by `send`, and a subclass can
      # make a private method public by redeclaring it. Each of those is worth having and
      # none of them is a check. This is the check: read the call site, resolve the constant,
      # and refuse any message an operation does not answer.
      #
      # `SettleInvoice.call(...)` is the door. `SettleInvoice.new`, `.build`, `.for`,
      # `.__perform__` and anything else is refused wherever it is written, whatever the
      # visibility of the thing it names.
      #
      # WHAT IT DOES NOT CATCH: the receiver must be a **constant this configuration can
      # resolve to a governed file**. An operation held in a variable is invisible — a
      # `command = SettleInvoice; command.new(...)` passes here, and so does anything reached
      # through `constantize` or a registry lookup.
      #
      # **What catches those is the runtime, and it was checked rather than assumed.**
      # `private_class_method :new, :allocate` refuses both through a variable, and an
      # operation has no other public class method to call because
      # `Shipshape/OneOperationOneClass` refuses declaring one. So the variable form fails on
      # its first run; this cop's job is to fail it at build time instead, in the form people
      # actually write. Chasing a constant through an assignment would buy the honest mistake
      # nothing — that mistake is written as a constant — and would not stop a deliberate
      # bypass, which has `constantize` either way.
      #
      # **Tests are exempt**: a test builds objects directly and reaches inside, which is what
      # a test is for.
      #
      # @example
      #   # bad
      #   SettleInvoice.new(invoice_id: 1)
      #   SettleInvoice.build_from(params)
      #
      #   # good
      #   SettleInvoice.call(actor: actor, invoice_id: 1)
      #
      #   # good — the small class-level API the base class provides
      #   SettleMonth.permissions
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

        # **A sequence runs its steps, it does not post them.** `call_later` inside a workflow
        # enqueues a step and carries on, so step three can start before step two has happened
        # and the order the workflow exists to state is not the order that runs. The workflow
        # then answers success for work that has not been done.
        #
        # The callee is deferrable — that is `DeferrableKinds` — and it is the *caller* that
        # may not defer. Both halves are needed: one says which operations own the method, the
        # other says from where it may be sent.
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

        # A class naming itself is not a call site reaching in. `Result.success(...)` inside
        # `Result` is one class talking to itself, and the door has nothing to say about it.
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

        # The door, plus the one class-level reader a caller may use: `permission`, which is
        # the operation's name and is what a label table and a seed are keyed by.
        #
        # **Neither `permits?` nor `permissions` is here, and they were removed together.**
        # `permits?` went private because the only reason to ask is to branch. Leaving
        # `permissions` allowed would have kept the same question in a longer spelling —
        # `SettleMonth.permissions.all? { |p| actor.may?(p) }` — and worse, one that disagrees
        # with the door: an anonymous operation reaching a guarded one demands nothing at its
        # own door and reports the inner permission here, so a view would hide a button the
        # door opens. A page offers the action and places the refusal, or a query hands it a
        # shape that already says what is offerable.
        #
        # **Per kind, not one flat list.** `call_later` exists only on the writing doors: a
        # workflow spans several transactions and a query answers nothing to nobody, so
        # neither has the method. Allowing it everywhere made `SomeWorkflow.call_later(…)`
        # pass this cop and fail at runtime with `NoMethodError` — the guard moving a failure
        # from the build to production, which is the opposite of its job.
        def allowed_for(kind)
          return allowed + deferring if deferrable_kinds.include?(kind)

          allowed
        end

        def allowed
          # **The fallback and `config/default.yml` say the same thing.** They drifted once —
          # the YAML dropped `permits?` and this kept it — and because `CopRunner` builds a
          # bare config, the cop's own test exercised the stale list and asserted the rule the
          # shipped config had just removed.
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
