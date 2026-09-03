# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      class EnforcementMessagesAreDocumentation < Base
        include Explains

        RAISES = :add_offense

        MODEL = <<~RUBY
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

        def on_new_investigation
          @cop_file = nil
        end

        def on_casgn(node)
          return unless cop_file?
          return unless message_constant?(node.children[1])

          text = literal(node.children[2])
          return if text.nil? || documents?(text)

          add_offense(node, message: message_for("`#{node.children[1]}`"))
        end

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
            instead: MODEL,
          )
        end

        # Something after each marker: checking only that both substrings appear accepted
        # `"Nope. WHY: INSTEAD:"`.
        def documents?(text)
          says_something_after?(text, Explains::WHY) && says_something_after?(text, Explains::INSTEAD)
        end

        def says_something_after?(text, marker)
          index = text.index(marker)
          return false unless index

          !text[(index + marker.length)..].to_s.strip.empty?
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

        # A call is trusted: a cop firing on code it cannot evaluate gets switched off.
        def literal(node)
          return unless node.respond_to?(:type)
          return unless %i[str dstr].include?(node.type)

          node.type == :str ? node.value : node.children.map { |part| literal(part) }.join
        end

        # `add_offense` is called by nothing but a cop, so no path list is needed and none can
        # go stale.
        def cop_file?
          return @cop_file unless @cop_file.nil?

          @cop_file = processed_source.ast&.each_node(:send)&.any? { |node| node.method_name == RAISES } || false
        end
      end
    end
  end
end
