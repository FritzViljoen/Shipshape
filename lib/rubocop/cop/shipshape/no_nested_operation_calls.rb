# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `an-operation-call-is-its-own-statement`.
      class NoNestedOperationCalls < Base
        include ReadsKinds

        RUNS = %i[call call_later].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)
          return unless operation_call?(node)

          nested(node).each { |inner| add_offense(inner, message: message_for(inner)) }
        end

        private

        # Reported from every enclosing call, and `add_offense` refuses a range it has already
        # taken — so a three-deep chain names each inner call once rather than once per level.
        def nested(node)
          node.arguments.flat_map { |argument| argument.each_node(:send).to_a }
              .select { |candidate| operation_call?(candidate) }
        end

        def operation_call?(node)
          RUNS.include?(node.method_name) && node.receiver&.const_type?
        end

        def message_for(node)
          name = node.receiver.source.sub(/\A::/, "")

          explain(
            "`#{name}.#{node.method_name}` is an argument to another operation's call.",
            because: "Two operations run in one statement, under one name, and the statement " \
                     "reads as one step. When it raises, the backtrace names the outer " \
                     "operation — so the call that actually failed is the one nobody can see, " \
                     "and the line is equally silent about which of the two answered nil. " \
                     "Naming the intermediate value also says what it *is*, which is the thing " \
                     "a reader of the seam needs and an argument list never states.",
            instead: SHAPE,
          )
        end

        SHAPE = <<~RUBY
          # each call is its own statement, and the value it answers has a name
          composition = FindOrderComposition.call(cart_id: cart_id)

          CreateOrder.call(composition: composition)
        RUBY

        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[request_handling entry_point workflow command query io_command io_query
               legacy_command legacy_query],
          )
        end
      end
    end
  end
end
