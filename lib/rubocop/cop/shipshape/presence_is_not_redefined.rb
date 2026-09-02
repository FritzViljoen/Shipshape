# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # `blank?` is `respond_to?(:empty?) ? !!empty? : !self`, so `empty?` decides `present?`
      # without naming it. All three are refused, or the ban is one method wide and two around.
      class PresenceIsNotRedefined < Base
        include ReadsKinds

        PRESENCE = %i[present? blank? empty?].freeze

        SILENT = <<~RUBY
          # a shape holds values and computes nothing, so it says nothing about presence
          class Basket < Shape
            def initialize(lines:)
              @lines = typed_array(lines, Line)
            end

            attr_reader :lines
          end

          # the caller asks the question it actually has
          if FindBasket.call(id: id).present?
        RUBY

        def on_def(node)
          return unless PRESENCE.include?(node.method_name)
          return unless one_of?(governed_kinds)

          add_offense(node, message: message_for(node.method_name))
        end
        alias on_defs on_def

        private

        def message_for(name)
          explain(
            "`#{name}` decides what `present?` answers about this shape.",
            because: "Request handling may test `present?` and nothing else, and it means one " \
                     "thing: did the query find anything. A shape that answers it for itself " \
                     "makes that question a rule — the action then takes an arm chosen by the " \
                     "shape rather than by whether there was an answer, and the branch reads " \
                     "the same either way. `nil` and `[]` are absent; a shape is present. That " \
                     "is the whole of it, and it is not the shape's to redefine.",
            instead: SILENT,
          )
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[shape])
        end
      end
    end
  end
end
