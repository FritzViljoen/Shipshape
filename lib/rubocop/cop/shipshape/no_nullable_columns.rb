# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      class NoNullableColumns < Base
        include Explains

        TABLE_FIRST = %i[
          add_column add_reference add_belongs_to
          change_column change_column_null change_column_default
        ].freeze

        # `timestamps` and `primary_key` are NOT NULL untold; `index` declares no column.
        COLUMN_TYPES = %i[
          string text integer bigint float decimal numeric datetime timestamp time date
          binary boolean json jsonb uuid inet cidr macaddr money interval column
          references belongs_to
        ].freeze

        NOT_NULL = <<~RUBY
          # the column refuses the gap
          t.string :nickname, null: false

          # nobody has said? That is the absence of a row, not a null in one.
          create_table :person_nicknames do |t|
            t.references :person, null: false, foreign_key: true
            t.string :nickname, null: false
          end
          # the unique index is half the fix — without it the join holds two answers
          add_index :person_nicknames, :person_id, unique: true

          # adding to a populated table: nullable, filled, promoted, one method
          add_column :people, :nickname, :string, null: true
          PersonRecord.update_all(nickname: "")
          change_column_null :people, :nickname, false
        RUBY

        def on_new_investigation
          @promoted = []
        end

        def on_def(node)
          @promoted = promotions_in(node)
        end

        def on_send(node)
          return if reversing?(node)
          return unless declares_a_column?(node)

          column = column_of(node)
          return if column.nil? || promoted?(column)

          return if options_cannot_be_read?(node)

          nullable = null_option(node)
          return if nullable == false

          add_offense(nullable || node, message: message_for(column, nullable.nil?))
        end

        private

        def declares_a_column?(node)
          return true if %i[add_column add_reference add_belongs_to change_column].include?(node.method_name)

          COLUMN_TYPES.include?(node.method_name) && node.receiver&.lvar_type? && node.arguments.any?
        end

        # Unreadable is not absent: reporting `NULL => false` as "says nothing" would fail a
        # column that is declared NOT NULL.
        def options_cannot_be_read?(node)
          options = node.arguments.last
          return false unless options.respond_to?(:hash_type?) && options.hash_type?

          options.pairs.any? { |pair| !pair.key.respond_to?(:value) }
        end

        # nil is "nothing was said", which is also nullable and the case worth catching.
        def null_option(node)
          options = node.arguments.last
          return unless options.respond_to?(:hash_type?) && options.hash_type?

          pair = options.pairs.find { |candidate| named?(candidate, :null) }
          return unless pair

          pair.value.true_type? ? pair : false
        end


        # `NULL => false` is legal Ruby, and a cop that raises leaves the file reported clean.
        def named?(pair, key)
          pair.key.respond_to?(:value) && pair.key.value == key
        end

        # `promotable?` is what stops the matching addition being reported when this cannot
        # read the column.
        def promotions_in(definition)
          return [] unless definition.body

          definition.body.each_node(:send).filter_map do |send|
            next unless send.method_name == :change_column_null
            next unless send.arguments.size >= 3 && send.arguments[2].false_type?

            name_of(send.arguments[1])
          end
        end

        def promoted?(column)
          Array(@promoted).include?(column)
        end

        def column_of(node)
          argument = TABLE_FIRST.include?(node.method_name) ? node.arguments[1] : node.arguments.first

          name_of(argument)
        end

        # Only a literal names a column; the caller drops the check rather than guessing.
        def name_of(argument)
          return unless argument.respond_to?(:type)
          return unless %i[sym str].include?(argument.type)

          argument.value.to_s
        end

        # Dropping a column, or the `down` half, is the reverse direction and exempt.
        def reversing?(node)
          %i[remove_column remove_reference remove_belongs_to].include?(node.method_name) ||
            node.each_ancestor(:def).any? { |definition| definition.method?(:down) }
        end

        def message_for(column, silent)
          said = silent ? "says nothing about `null:`, which means nullable" : "is nullable"

          explain(
            "`#{column}` #{said}, so every row that holds no value holds the same " \
            "unreadable one.",
            because: "A null is not \"off\", not \"inherit\", not \"not applicable\", not " \
                     "\"we lost it\" — it is all of them at once, and no reader can tell " \
                     "which. Every meaning given to it is a fact nobody declared, so the " \
                     "meaning lives in whichever read happens to be reading, and two " \
                     "reads disagree.",
            instead: NOT_NULL,
          )
        end
      end
    end
  end
end
