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
      # resolve to a governed file**. An operation held in a variable — `klass = SettleInvoice;
      # klass.build` — is invisible, and so is one reached through a constant in a tree the
      # layout does not declare. **Tests are exempt**: a test builds objects directly and
      # reaches inside, which is what a test is for.
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
          return if allowed.include?(node.method_name.to_s)
          return unless operation?(name)
          return if refers_to_itself?(name)

          add_offense(node, message: message_for(name, node.method_name))
        end

        private

        def operation?(name)
          governed_kinds.include?(kinds.for_constant(name))
        end

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

        # The door, plus the small class-level API the base classes provide for asking about
        # an operation without running it — a view hiding a button it may not offer needs
        # `permissions`, and the permission catalogue needs `permission`.
        def allowed
          @allowed ||= cop_config.fetch("AllowedMessages", %w[call permission permissions permits? anonymous?])
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
