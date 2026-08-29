# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the leaving half of `nothing-travels-off-the-call-path`.
      #
      # **This is the action-at-a-distance cop, and nothing else in the canon catches it.**
      # The other guards work because the cause is findable by reading. Here the cause is
      # perfectly visible and it is the *effect* that cannot be found: something changed, and
      # the place it changed has no textual connection to the place that changed it.
      #
      # WHAT IT DOES NOT CATCH: the list is **closed**. **Reopening another class is not
      # caught**, deliberately — nothing syntactic separates reopening from defining, and a
      # guard that fires on an ordinary nested class is a guard somebody switches off.
      # Mutating a collaborator reached
      # *through* a handed-in object is legal here and can still act at a distance — nothing
      # catches that. `send`-based writes are invisible, as is a gem doing this on your
      # behalf.
      #
      # @example
      #   # bad — the effect is unfindable from the code it breaks
      #   $current_tenant = tenant
      #   Settings::CACHE[:rate] = rate
      #   Config.rate = rate
      #
      #   # good — it comes back as a value the caller can see
      #   success(Receipt.new(tenant: tenant, rate: rate))
      class NoDistantWrites < Base
        include ReadsKinds

        def on_gvasgn(node)
          offend(node, "`#{node.children.first}` is a global.")
        end

        def on_cvasgn(node)
          offend(node, "`#{node.children.first}` is a class variable shared with every subclass.")
        end

        # Ruby spells comparison with a trailing `=` too, so a name ending in `=` is not
        # enough to mean assignment. `Booking::HELD == @state` reads nothing and writes
        # nothing, and reporting it was how this cop fired on every guard clause in the
        # codebase.
        COMPARISONS = %i[== != <= >= === =~ !~].freeze

        # `SETTINGS[:rate] = 1` and `SETTINGS << row` — mutating a constant in place.
        def on_send(node)
          return if COMPARISONS.include?(node.method_name)
          return unless %i[[]= <<].include?(node.method_name) || node.method_name.to_s.end_with?("=")
          return unless node.receiver&.const_type?

          offend(node, "`#{node.receiver.source}` is a constant, and this changes it in place.")
        end

        private

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

        RETURNED = <<~RUBY
          # the change comes back as a value, so the call site can see it
          class SwitchTenant < Command
            def call
              success(Session.new(tenant: @tenant))
            end
          end

          # and it is handed to whoever needs it, by name
          RunReport.call(session: result.value)
        RUBY

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query shape])
        end
      end
    end
  end
end
