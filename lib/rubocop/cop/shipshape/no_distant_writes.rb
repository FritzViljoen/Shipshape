# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"
require "rubocop/cop/shipshape/no_callbacks"

module RuboCop
  module Cop
    module Shipshape
      # Holds the leaving half of `nothing-travels-off-the-call-path`, including pub/sub —
      # see `subscription_call?`, which reuses `NoCallbacks::HOOKS` rather than re-listing it.
      class NoDistantWrites < Base
        include ReadsKinds

        RETURNED = <<~RUBY
          # the change comes back as a value, so the call site can see it
          class SwitchTenant < Deed
            def call
              success(Session.new(tenant: @tenant))
            end
          end

          # and it is handed to whoever needs it, by name
          RunReport.call(session: result.value)
        RUBY

        def on_gvasgn(node)
          offend(node, "`#{node.children.first}` is a global.")
        end

        def on_cvasgn(node)
          offend(node, "`#{node.children.first}` is a class variable shared with every subclass.")
        end

        # A name ending in `=` is not assignment: `Booking::HELD == @state` reads and writes
        # nothing, and reporting it fired this cop on every guard clause in the codebase.
        COMPARISONS = %i[== != <= >= === =~ !~].freeze

        # A hook attached to a named constant rather than written inside it — see the law.
        ATTACHED_CALLBACKS = NoCallbacks::HOOKS

        # `Notifications`-suffixed receivers only — unlike the hooks above, ordinary words.
        NOTIFICATIONS_METHODS = %i[subscribe instrument].freeze

        def on_send(node)
          return if COMPARISONS.include?(node.method_name)
          return offend_subscription(node) if subscription_call?(node)
          return unless %i[[]= <<].include?(node.method_name) || node.method_name.to_s.end_with?("=")
          return unless node.receiver&.const_type?

          offend(node, "`#{node.receiver.source}` is a constant, and this changes it in place.")
        end

        private

        def subscription_call?(node)
          return false unless node.receiver&.const_type?

          ATTACHED_CALLBACKS.include?(node.method_name) || notifications_call?(node)
        end

        def notifications_call?(node)
          NOTIFICATIONS_METHODS.include?(node.method_name) && node.receiver.source.end_with?("Notifications")
        end

        def offend_subscription(node)
          offend(node, "`#{node.receiver.source}.#{node.method_name}` hands a handler to a " \
                       "table resolved by lookup at runtime, not to a call this file makes.")
        end

        def offend(node, what)
          return unless one_of?(governed_kinds)

          add_offense(node, message: message_for(what))
        end

        def message_for(what)
          explain(
            "#{what} Writing it here changes something the caller cannot see from the call.",
            because: "This is action at a distance, and it is the one defect nothing else " \
                     "here catches. The cause is perfectly visible; the *effect* is not — " \
                     "the code that breaks has no textual connection to the code that " \
                     "broke it, so it is found by bisecting rather than by reading. Two " \
                     "operations running in one process also now share it.",
            instead: RETURNED,
          )
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow deed question io_deed io_question shape])
        end
      end
    end
  end
end
