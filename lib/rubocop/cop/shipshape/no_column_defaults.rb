# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-database-defaults`. Creation and update timestamps excepted.
      class NoColumnDefaults < Base
        include Explains

        TIMESTAMPS = %w[created_at updated_at].freeze

        TABLE_FIRST = %i[
          add_column add_reference add_belongs_to change_column change_column_default
        ].freeze

        def on_send(node)
          # `change_column_default` states the default positionally, with no `default:` to find.
          return positional_default(node) if node.method_name == :change_column_default

          default = default_option(node)
          return unless default

          column = column_of(node)
          return if column.nil? || TIMESTAMPS.include?(column)

          add_offense(default, message: message_for(column, default.value.source))
        end

        private

        def positional_default(node)
          column = column_of(node)
          return if column.nil? || TIMESTAMPS.include?(column)

          stated = node.arguments[2]
          return unless stated

          if stated.hash_type?
            pair = stated.pairs.find { |candidate| named?(candidate, :to) }
            return unless pair

            stated = pair.value
          end

          # A nil default REMOVES one: the canonical spelling of the fix this cop asks for.
          return if stated.nil_type?

          add_offense(node, message: message_for(column, stated.source))
        end

        def default_option(node)
          options = node.arguments.last
          return unless options.respond_to?(:hash_type?) && options.hash_type?

          options.pairs.find { |candidate| named?(candidate, :default) }
        end

        # `NULL => false` is legal Ruby, and a cop that raises leaves the file reported clean.
        def named?(pair, key)
          pair.key.respond_to?(:value) && pair.key.value == key
        end

        def column_of(node)
          argument = TABLE_FIRST.include?(node.method_name) ? node.arguments[1] : node.arguments.first
          return unless argument.respond_to?(:type)
          return unless %i[sym str].include?(argument.type)

          argument.value.to_s
        end

        def message_for(column, value)
          explain(
            "`#{column}` carries a database default of `#{value}`, which is a second place " \
            "deciding this value.",
            because: "The domain already names the fallback, so the fact is declared " \
                     "twice and the two drift. A reader then cannot say what the system " \
                     "holds — not because nothing states it, but because two things do " \
                     "and they disagree. A row written outside the application silently " \
                     "gets the schema's answer instead of the domain's.",
            instead: <<~RUBY,
              # the column refuses the gap
              t.string :state, null: false

              # the domain names the fallback, in one place, where it can be read
              class CreateBooking < Command
                def call
                  BookingRecord.create!(state: @state || Booking::HELD)
                end
              end
            RUBY
          )
        end
      end
    end
  end
end
