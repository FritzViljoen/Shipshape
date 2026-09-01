# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Scoped by kind, never by a list of base classes: naming `ViewComponent::Base` covered
      # that one gem and left Phlex, ActionView and a house base uncovered, which is the copy
      # of a fact this canon refuses. A class inheriting one already governed is swept by it.
      class PresentationHoldsNoRecords < Base
        include ReadsKinds

        SWEEP = "HoldsNoRecords"

        def on_class(node)
          return unless one_of?(governed_kinds)
          return if inherits_a_governed_class?(node)
          return if extends_the_sweep?(node)

          add_offense(node.identifier, message: message_for(node.identifier.source))
        end

        private

        def inherits_a_governed_class?(node)
          parent = node.parent_class
          return false unless parent&.const_type?

          governed_kinds.include?(kinds.for_constant(parent.source.sub(/\A::/, "")))
        end

        def extends_the_sweep?(node)
          node.body&.each_node(:send)&.any? do |send|
            send.method?(:extend) && send.first_argument&.const_type? &&
              send.first_argument.source.sub(/\A::/, "") == sweep
          end
        end

        def message_for(name)
          explain(
            "Nothing sweeps `#{name}`, so a record handed to it stays.",
            because: "A record is only allowed in a command or a query, and the matrix holds " \
                     "that where the record is NAMED. It can say nothing about one arriving " \
                     "as an argument — `#{name}.new(person: person)` names no record at all — " \
                     "so the object is asked instead. The sweep is inherited, which is why a " \
                     "class below a swept base needs nothing; this is the base itself, or a " \
                     "class standing on its own outside one.",
            instead: <<~RUBY
              class #{name} < ApplicationViewComponent   # or Shape, or your own swept base
              end

              # standing on its own? then it does the asking itself
              class #{name}
                include TypedArguments

                extend #{sweep}
              end
            RUBY
          )
        end

        def sweep
          cop_config.fetch("Sweep", SWEEP)
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[shape view_component])
        end
      end
    end
  end
end
