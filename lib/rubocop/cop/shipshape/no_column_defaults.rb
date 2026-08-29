# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-database-defaults`. Creation and update timestamps excepted.
      #
      # A default in the schema is a second place deciding a value, and it drifts from the
      # first. The column refuses the gap; the domain names the fallback.
      #
      # **A general-purpose cop that wants a default alongside NOT NULL** so a migration
      # survives a populated table conflicts with this directly. Turn that cop off — the
      # promotion rule in `Shipshape/NoNullableColumns` is the answer it was reaching for.
      #
      # WHAT IT DOES NOT CATCH: migrations only, so a default applied by hand or by a
      # database-side trigger is invisible. It also cannot see a default expressed as a
      # column's generated-value clause rather than as a default.
      #
      # @example
      #   # bad — two declarations of one fact, and they drift
      #   t.string :state, null: false, default: "held"
      #
      #   # good — the column refuses the gap, the domain names the fallback
      #   t.string :state, null: false
      class NoColumnDefaults < Base
        include Explains

        TIMESTAMPS = %w[created_at updated_at].freeze
        ADDERS = %i[add_column add_reference add_belongs_to].freeze

        def on_send(node)
          default = default_option(node)
          return unless default

          column = column_of(node)
          return if TIMESTAMPS.include?(column)

          add_offense(default, message: message_for(column, default.value.source))
        end

        private

        def default_option(node)
          options = node.arguments.last
          return unless options.respond_to?(:hash_type?) && options.hash_type?

          options.pairs.find { |candidate| candidate.key.value == :default }
        end

        def column_of(node)
          argument = ADDERS.include?(node.method_name) ? node.arguments[1] : node.arguments.first
          return "" unless argument

          argument.respond_to?(:value) ? argument.value.to_s : argument.source
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
