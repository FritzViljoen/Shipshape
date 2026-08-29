# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-type-interrogation`.
      #
      # Asking an object what class it is, in order to decide what to do with it. The ask is
      # the branch that should have been a class.
      #
      # **Asserting a type is a different act and is allowed.** The difference is what
      # happens next: an assertion has one outcome, a dispatch has two. So the argument guard
      # is exempt by name, and nothing else is.
      #
      # WHAT IT DOES NOT CATCH: a genuine boundary check written outside that helper is a
      # false positive, and it is meant to be argued in review rather than suppressed in
      # silence — a disable comment on this cop should be rare enough to notice.
      # Deserialisation and adapter code at a real edge often need the ask, which is why
      # those trees sit outside the cop's scope rather than being exempted inside it.
      #
      # @example
      #   # bad — two outcomes, so it is a dispatch
      #   def rate
      #     @party.is_a?(Group) ? group_rate : single_rate
      #   end
      #
      #   # good — the variants answer for themselves
      #   @party.rate
      class NoTypeInterrogation < Base
        include ReadsKinds

        ASKS = %i[is_a? kind_of? instance_of? respond_to?].freeze
        ASSERTS = %i[typed typed_array typed_hash].freeze

        def on_send(node)
          return unless ASKS.include?(node.method_name)
          return unless one_of?(governed_kinds)
          return if asserting?(node)

          add_offense(node, message: message_for(node))
        end

        # `case supplier when Contract then ... end` — a dispatch spelled as a case.
        def on_case(node)
          return unless node.condition
          return unless one_of?(governed_kinds)

          node.when_branches.each do |branch|
            branch.conditions.select(&:const_type?).each do |const|
              add_offense(const, message: case_message(const))
            end
          end
        end

        private

        def message_for(node)
          explain(
            "`#{node.method_name}` asks what kind of thing this is, and the answer " \
            "decides what happens next.",
            because: "A variant that has to be asked about is not substitutable — it is a " \
                     "different thing wearing a shared name. The ask is the branch that " \
                     "should have been a class, and every new variant means finding every " \
                     "site that asks.",
            instead: SHAPE,
          )
        end

        def case_message(const)
          explain(
            "This `case` dispatches on `#{const.source}`, which is a chain of `is_a?` " \
            "with better syntax.",
            because: "Each variant's behaviour ends up here, in the caller, instead of in " \
                     "the variant. Adding one means editing this file, and the branch that " \
                     "was forgotten is found in production.",
            instead: SHAPE,
          )
        end

        SHAPE = <<~RUBY
          # each variant answers for itself; adding one adds a class and edits nothing
          class GroupParty < Shape
            def rate = @head_count * @unit_rate * 0.9
          end

          class SoloParty < Shape
            def rate = @unit_rate
          end

          party.rate   # the caller no longer knows there are two

          # asserting is not dispatching — one outcome, so it stays legal
          @party = typed(party, Party)
        RUBY

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query shape])
        end

        # `typed(value, Date)` is an assertion; a bare `value.is_a?(Date)` inside the guard
        # itself is that assertion's own implementation.
        def asserting?(node)
          node.each_ancestor(:send).any? { |ancestor| ASSERTS.include?(ancestor.method_name) } ||
            node.each_ancestor(:def).any? { |ancestor| ASSERTS.include?(ancestor.method_name) }
        end
      end
    end
  end
end
