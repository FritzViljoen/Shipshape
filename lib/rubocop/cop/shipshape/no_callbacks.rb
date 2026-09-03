# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-lifecycle-callbacks`.
      class NoCallbacks < Base
        include ReadsKinds

        HOOKS = %i[
          before_validation after_validation
          before_save around_save after_save
          before_create around_create after_create
          before_update around_update after_update
          before_destroy around_destroy after_destroy
          after_commit after_create_commit after_update_commit after_destroy_commit
          after_save_commit
          after_rollback after_initialize after_find after_touch
        ].freeze

        NAMED = <<~RUBY
          # the operation that wanted the work says so, by name and in order
          class ConfirmBooking < Command
            def call
              RecalculateTotals.call(booking: @booking)
              success(@booking)
            end
          end
        RUBY

        def on_send(node)
          return unless node.receiver.nil? && HOOKS.include?(node.method_name)
          return unless one_of?(record_kinds)

          add_offense(node, message: message_for(node))
        end

        private

        def message_for(node)
          explain(
            "`#{node.method_name}` hides work behind `save`.",
            because: "The caller reads one method and gets several, in an order nothing " \
                     "states, and a failure in any of them is attributed to the save. A " \
                     "codebase with these cannot be read by following calls.",
            instead: NAMED,
          )
        end

        def record_kinds
          cop_config.fetch("Kinds", %w[record])
        end
      end
    end
  end
end
