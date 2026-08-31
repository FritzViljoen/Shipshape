# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      class ShapeIsComposed < Base
        include ReadsKinds

        def on_def(node)
          return unless node.method?(:initialize)
          return unless one_of?(shape_kinds)

          keywords = node.arguments.select { |argument| %i[kwarg kwoptarg].include?(argument.type) }
          names = keywords.map { |keyword| keyword.name.to_s }

          keywords.each do |keyword|
            owner = flattened_from(keyword.name.to_s, names)
            next unless owner

            add_offense(keyword, message: message_for(keyword.name, owner))
          end
        end

        private

        # `supplier_name` is flattened when `supplier_email` is here too: one prefix, more
        # than one field. A single prefixed keyword is just a name, and is left alone —
        # firing on `person_id` alone would make this cop worthless within a week.
        def flattened_from(name, names)
          prefix = name.split("_").first
          return if prefix == name

          siblings = names.count { |other| other.start_with?("#{prefix}_") }
          return unless siblings >= minimum_fields

          prefix
        end

        def message_for(name, owner)
          held = camelize(owner)

          explain(
            "`#{name}:` copies a field off `#{held}` instead of holding the `#{held}`.",
            because: "A flattened field is the first column of the next god object — this " \
                     "is the mechanism by which a hundred-column table happens, one " \
                     "reasonable addition at a time. A change to what a #{owner} is now " \
                     "touches two classes, and the copies drift until nobody can say which " \
                     "one is right.",
            instead: <<~RUBY,
              # it holds the other object, so there is one home for what a #{owner} is
              class Booking < Shape
                def initialize(reference:, #{owner}:)
                  @reference = typed(reference, String)
                  @#{owner} = typed(#{owner}, #{held})
                end
              end

              # a part that belongs to this object and nothing else nests inside it
              class Booking::Line < Shape
                def initialize(description:, amount:)
                  @description = typed(description, String)
                  @amount = typed(amount, Money)
                end
              end
            RUBY
          )
        end

        def camelize(word)
          word.split("_").map(&:capitalize).join
        end

        def minimum_fields
          cop_config.fetch("MinimumFields", 2)
        end

        def shape_kinds
          cop_config.fetch("Kinds", %w[shape])
        end
      end
    end
  end
end
