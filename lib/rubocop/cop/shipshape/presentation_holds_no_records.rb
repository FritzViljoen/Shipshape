# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Matches the superclass as written, so it reaches a base the installer wrote and one the
      # application already had. A leaf inheriting the library base directly is the same gap.
      class PresentationHoldsNoRecords < Base
        include Explains

        BASES = ["ViewComponent::Base"].freeze

        SWEEP = "HoldsNoRecords"

        def on_class(node)
          parent = node.parent_class
          return unless parent&.const_type?
          return unless bases.include?(parent.source.sub(/\A::/, ""))
          return if extends_the_sweep?(node)

          add_offense(node.identifier, message: message_for(node.identifier.source, parent.source))
        end

        private

        def extends_the_sweep?(node)
          node.body&.each_node(:send)&.any? do |send|
            send.method?(:extend) && send.first_argument&.const_type? &&
              send.first_argument.source.sub(/\A::/, "") == sweep
          end
        end

        def bases
          cop_config.fetch("Bases", BASES)
        end

        def sweep
          cop_config.fetch("Sweep", SWEEP)
        end

        def message_for(name, parent)
          explain(
            "`#{name}` inherits `#{parent}` and does not extend `#{sweep}`.",
            because: "A record handed to a component can lazily load an association, write " \
                     "through it, and reopen a query inside a view. The call graph refuses a " \
                     "record being NAMED out of place, and can say nothing about one arriving " \
                     "as an argument — `Card.new(person: PersonRecord.find(1))` names no " \
                     "record at the component. The sweep is what asks the object instead, and " \
                     "it is inherited, so the class that inherits the library's base is where " \
                     "it has to go. An application that already had such a base never " \
                     "inherits the generated one, and nothing else reports the absence: the " \
                     "components are still governed by path, so the tree looks covered.",
            instead: <<~RUBY
              class #{name} < #{parent}
                include TypedArguments

                # asked of the object, because an argument names no constant for a cop to see
                extend #{sweep}
              end
            RUBY
          )
        end
      end
    end
  end
end
