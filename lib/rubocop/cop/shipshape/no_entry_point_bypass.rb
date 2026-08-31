# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the caller's half of `an-operation-is-a-leaf`.
      class NoEntryPointBypass < Base
        include Explains

        SENDERS = %i[send __send__ public_send method].freeze

        def on_send(node)
          return unless SENDERS.include?(node.method_name)

          named = literal_name(node.arguments.first)
          return unless entry_names.include?(named)

          add_offense(node, message: message_for(node.method_name, named))
        end

        private

        def literal_name(argument)
          return unless argument.respond_to?(:type) && %i[sym str].include?(argument.type)

          argument.value.to_s
        end

        def message_for(sender, named)
          explain(
            "`#{sender}(:#{named})` builds an operation without going through the door.",
            because: "The constructor is private so that `call` is the only way in, and " \
                     "`call` is where the permission check runs, where the transaction " \
                     "opens, and where the return type is asserted. An operation built this " \
                     "way has skipped all three, and the line reads like ordinary code. " \
                     "`private` is a convention in Ruby rather than a wall, so nothing the " \
                     "operation does can refuse this; the refusal has to be here.",
            instead: <<~RUBY,
              # the door, which is the only supported way in
              SettleInvoice.call(actor: actor, invoice_id: 1)

              # in a test this is allowed and this cop is silent — but what the door does
              # IS part of the behaviour, so a test that builds around it passes while the
              # operation is unauthorised. Prefer going through it there too.
            RUBY
          )
        end

        # Construction is what is closed: `new` and `allocate` build an operation without
        # `call`, `__perform__` runs one without the check, and both need `send` to reach.
        def entry_names
          @entry_names ||= Array(cop_config.fetch("Constructor", %w[new allocate])) +
                           Array(cop_config.fetch("Forwarder", "__perform__"))
        end
      end
    end
  end
end
