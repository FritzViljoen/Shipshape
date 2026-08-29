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
      # WHAT IT DOES NOT CATCH: a `when` naming a SCREAMING_CASE constant is read as a
      # value rather than a class, so a class named that way is missed. A genuine boundary
      # check written outside that helper is a
      # false positive, and it is meant to be argued in review rather than suppressed in
      # silence — a disable comment on this cop should be rare enough to notice.
      # Deserialisation and adapter code at a real edge often need the ask, which is why
      # those trees sit outside the cop's scope rather than being exempted inside it.
      #
      # @example
      #   # bad — two outcomes, so it is a dispatch. All four spell the same ask.
      #   @party.is_a?(Group) ? group_rate : single_rate
      #   @party.class == Group
      #   @party.class.name == "Group"
      #   Group === @party
      #
      #   # good — the variants answer for themselves
      #   @party.rate
      class NoTypeInterrogation < Base
        include ReadsKinds

        ASKS = %i[is_a? kind_of? instance_of? respond_to?].freeze
        ASSERTS = %i[typed typed_array typed_hash].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)

          if ASKS.include?(node.method_name)
            return if asserting?(node)

            add_offense(node, message: message_for(node))
          elsif compares_class?(node)
            add_offense(node, message: message_for(node))
          end
        end

        # `case supplier when Contract then ... end` — a dispatch spelled as a case.
        def on_case(node)
          return unless node.condition
          return unless one_of?(governed_kinds)

          node.when_branches.each do |branch|
            branch.conditions.select { |condition| dispatches_on_a_class?(condition) }.each do |const|
              add_offense(const, message: case_message(const))
            end
          end
        end

        private

        # `when Group` dispatches on a class. `when Booking::HELD` compares against a value
        # that happens to be a constant — Ruby's own convention separates them, and failing
        # the second was this cop firing on every state machine in the codebase.
        # `@party.class == Group`, `@party.class.name == "Group"` and `Group === @party` ask
        # exactly what `is_a?` asks. The law names the act, not the spelling.
        def compares_class?(node)
          return true if node.method_name == :=== && dispatches_on_a_class?(node.receiver)
          return false unless %i[== !=].include?(node.method_name)

          [node.receiver, node.arguments.first].compact.any? { |side| reads_the_class?(side) }
        end

        def reads_the_class?(side)
          return false unless side.respond_to?(:send_type?) && side.send_type?

          side.method_name == :class || (side.method_name == :name && side.receiver&.send_type? &&
            side.receiver.method_name == :class)
        end

        def dispatches_on_a_class?(condition)
          return false unless condition.const_type?

          condition.source.split("::").last !~ /\A[A-Z0-9_]+\z/
        end

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
