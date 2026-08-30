# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the caller's half of `an-operation-is-a-leaf`.
      #
      # An operation's constructor is private, so `SettleInvoice.call(...)` is the only way
      # in: nobody outside can build one, which is what makes the public `call` on the
      # instance harmless. **`private` in Ruby is a convention, not a wall** — `send` steps
      # around it, and a caller that builds an operation directly then reaches its `call` has
      # skipped the permission check, the transaction and the return-type assertion while
      # writing something that reads like ordinary code.
      #
      # This is the one cop whose subject is the **call site** rather than the class. The
      # class cannot defend itself here: nothing an operation does can stop `send`.
      #
      # WHAT IT DOES NOT CATCH: the method name must be a **literal**. `send(verb)` where
      # `verb` is a variable is invisible, and so is `method(:call).to_proc`, and so is
      # anything reached through `instance_eval`. It is a closed list of three senders, and a
      # gem that wraps `send` on your behalf is outside it. **Tests are exempt**: a test
      # reaching a private method is what a test is for, and refusing it would make this the
      # first cop a team turns off. The generated base classes are excluded by path — they are where the legitimate `send` lives, and excluding them by
      # name would have excluded every application file called `command.rb`.
      #
      # @example
      #   # bad — the door is right there, and this went around it
      #   SettleInvoice.send(:new, invoice_id: 1).call
      #
      #   # good
      #   SettleInvoice.call(actor: actor, invoice_id: 1)
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

        # **Construction is what is closed**, so this is what a bypass reaches for. `call`
        # is public and harmless — there is no operation to call it on unless somebody built
        # one, and `private_class_method :new` is what stops that.
        # **Both doors.** `new` builds an operation without going through `call`;
        # `__perform__` runs one without the permission check, the transaction or the
        # return-type assertion. Neither is reachable without `send`, which is why this cop
        # is the one that closes them.
        def entry_names
          @entry_names ||= Array(cop_config.fetch("Constructor", "new")) +
                           Array(cop_config.fetch("Forwarder", "__perform__"))
        end
      end
    end
  end
end
