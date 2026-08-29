# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `enforcement-messages-are-documentation`, over the enforcement itself.
      #
      # **This is the one cop whose subject is cops** — this gem's and any the application
      # writes. `add_offense` is the marker: nothing but a cop calls it, so no path list is
      # needed and none can go stale.
      #
      # A rule that only exists in a document is a rule most people will never read. The
      # failure is where it is actually delivered — and for an agent the failure is the
      # *entire* context: no session memory, no design document, no colleague to ask. A
      # message reading "avoid this" leaves the reader with two options, neither of them the
      # rule: guess, or disable the cop. They disable the cop.
      #
      # So a message states what is wrong, WHY the rule exists, and INSTEAD a correct example
      # short enough to copy. `Explains#explain` takes all three as required arguments, which
      # is why calling it satisfies this cop outright.
      #
      # WHAT IT DOES NOT CATCH: whether the example is any good, or whether the reason is
      # true. It reads literals, so a message assembled by a helper it cannot evaluate is
      # passed — route those through `explain` and the shape is structural rather than
      # checked.
      #
      # @example
      #   # bad — the reader learns that something is wrong, and nothing else
      #   MSG = "Do not use lifecycle callbacks."
      #
      #   # bad — same, inline
      #   add_offense(node, message: "Controller should not branch here")
      #
      #   # good — the three parts, guaranteed by the signature
      #   add_offense(node, message: explain(
      #     "`before_save` hides work behind `save`.",
      #     because: "The caller reads one method and gets several, in an order nothing " \
      #              "states, and a failure in any of them is attributed to the save.",
      #     instead: <<~RUBY,
      #       class ConfirmBooking < Command
      #         def call
      #           RecalculateTotals.call(booking: @booking)
      #           success(@booking)
      #         end
      #       end
      #     RUBY
      #   ))
      class EnforcementMessagesAreDocumentation < Base
        include Explains

        RAISES = :add_offense

        def on_new_investigation
          @cop_file = nil
        end

        # A constant message: `MSG = "..."`, `MSG_SOMETHING = "..."`, `MESSAGE = <<~TEXT`.
        def on_casgn(node)
          return unless cop_file?
          return unless message_constant?(node.children[1])

          text = literal(node.children[2])
          return if text.nil? || documents?(text)

          add_offense(node, message: message_for("`#{node.children[1]}`"))
        end

        # An inline message: `add_offense(node, message: "...")`.
        def on_send(node)
          return unless node.method_name == RAISES
          return unless cop_file?

          given = passed_message(node)
          text = literal(given)
          return if text.nil? || documents?(text)

          add_offense(given, message: message_for("This message"))
        end

        private

        def message_for(subject)
          explain(
            "#{subject} states a rule without saying why it exists or what to write " \
            "instead. It is the only thing a reader — and the whole of what an agent — " \
            "gets when this cop fires.",
            because: "A message that only says something is wrong leaves two options, " \
                     "neither of them the rule: guess, or disable the cop. They disable " \
                     "the cop. The failure is where a rule is actually delivered, so it " \
                     "carries the reason and a correct example, not a restatement of the " \
                     "cop's own name.",
            instead: <<~RUBY,
              # `explain` takes all three parts as required arguments, so none can be left out
              add_offense(node, message: explain(
                "`before_save` hides work behind `save`.",
                because: "The caller reads one method and gets several, in an order " \\
                         "nothing states, and a failure in any of them is attributed " \\
                         "to the save.",
                instead: <<~EXAMPLE,
                  class ConfirmBooking < Command
                    def call
                      RecalculateTotals.call(booking: @booking)
                      success(@booking)
                    end
                  end
                EXAMPLE
              ))
            RUBY
          )
        end

        # Both markers, and something after each of them. `explain` puts them there; a
        # hand-written message is welcome to, and passes on the same terms.
        def documents?(text)
          text.include?(Explains::WHY) && text.include?(Explains::INSTEAD)
        end

        def message_constant?(name)
          name.to_s.start_with?("MSG") || name.to_s.include?("MESSAGE")
        end

        def passed_message(node)
          options = node.arguments.last
          return unless options.respond_to?(:hash_type?) && options.hash_type?

          pair = options.pairs.find { |candidate| candidate.key.value == :message }
          pair&.value
        end

        # Only a literal can be read here. A call is trusted — `explain` is the reason the
        # call exists, and a cop that fires on code it cannot evaluate is a cop that gets
        # switched off wholesale.
        def literal(node)
          return unless node.respond_to?(:type)
          return unless %i[str dstr].include?(node.type)

          node.type == :str ? node.value : node.children.map { |part| literal(part) }.join
        end

        # `add_offense` is defined by RuboCop and called by nothing else, so its presence is
        # what makes this a cop. Derived from the file rather than from a path list, which
        # means a cop in an unusual directory is still governed and a moved directory needs
        # no edit here.
        def cop_file?
          return @cop_file unless @cop_file.nil?

          @cop_file = processed_source.ast&.each_node(:send)&.any? { |node| node.method_name == RAISES } || false
        end
      end
    end
  end
end
