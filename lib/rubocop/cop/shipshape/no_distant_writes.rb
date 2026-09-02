# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the leaving half of `nothing-travels-off-the-call-path`.
      class NoDistantWrites < Base
        include ReadsKinds

        RETURNED = <<~RUBY
          # the change comes back as a value, so the call site can see it
          class SwitchTenant < Write
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

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow write read io_write io_read shape])
        end
      end
    end
  end
end
