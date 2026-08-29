# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-nullable-columns`.
      #
      # A null is not "off", not "inherit", not "not applicable", not "we lost it" — it is
      # all of them at once, and no reader can tell which.
      #
      # **A column with no `null:` at all is nullable, and that is how nearly every nullable
      # column arrives.** Catching only an explicit `null: true` would have been a guard
      # shaped like coverage: the common case writes nothing.
      #
      # **A column may be nullable between two statements of one migration method.** A NOT
      # NULL column cannot be added to a populated table in one statement, so it is added
      # nullable, filled, and promoted — and the promotion comes later in the same method.
      #
      # WHAT IT DOES NOT CATCH: it reads **migrations, not the live schema**. A column made
      # nullable by a hand-run statement, a tool or a vendored migration is invisible, so a
      # passing run proves what this repo's migrations did, not what the database holds. A
      # promotion whose column is not a literal — built in a loop, or from a constant — is
      # not read, and the add in that same loop is not reported either, because a guard that
      # cannot see the promotion must not fail the addition.
      #
      # @example
      #   # bad — both of these are nullable
      #   t.string :nickname, null: true
      #   t.string :nickname
      #
      #   # good — the column refuses the gap
      #   t.string :nickname, null: false
      #
      #   # good — added nullable, filled, promoted, all in one method
      #   add_column :people, :nickname, :string, null: true
      #   PersonRecord.update_all(nickname: "")
      #   change_column_null :people, :nickname, false
      class NoNullableColumns < Base
        include Explains

        # `add_column :people, :nickname, :string` — table first, column second.
        TABLE_FIRST = %i[
          add_column add_reference add_belongs_to
          change_column change_column_null change_column_default
        ].freeze

        # `t.string :nickname` — column first. `timestamps` and `primary_key` are NOT NULL
        # without being told, and `index` declares no column at all.
        COLUMN_TYPES = %i[
          string text integer bigint float decimal numeric datetime timestamp time date
          binary boolean json jsonb uuid inet cidr macaddr money interval column
          references belongs_to
        ].freeze

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

        # A key this cop cannot read — `NULL => false` — means it cannot tell what was
        # said. Unreadable is not absent, and reporting it as "says nothing" would fail a
        # column that is declared NOT NULL.
        def options_cannot_be_read?(node)
          options = node.arguments.last
          return false unless options.respond_to?(:hash_type?) && options.hash_type?

          options.pairs.any? { |pair| !pair.key.respond_to?(:value) }
        end

        # Answers the `null:` pair node when it is `true`, `false` when the column is
        # declared NOT NULL, and nil when nothing was said — which is also nullable, and is
        # the case worth catching.
        def null_option(node)
          options = node.arguments.last
          return unless options.respond_to?(:hash_type?) && options.hash_type?

          pair = options.pairs.find { |candidate| named?(candidate, :null) }
          return unless pair

          pair.value.true_type? ? pair : false
        end


        # `NULL => false` is legal Ruby. `candidate.key.value` raises on it, and a cop that
        # raises leaves the file reported as clean.
        def named?(pair, key)
          pair.key.respond_to?(:value) && pair.key.value == key
        end

        # `change_column_null :people, :nickname, false` — the promotions this method makes.
        # A non-literal column is skipped rather than crashed on; `promotable?` is what stops
        # the matching addition being reported when this cannot read it.
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

        # Only a literal names a column. Anything else — a local from a loop, a constant —
        # is unreadable here, and the caller drops the check rather than guessing.
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
                     "meaning lives in whichever query happens to be reading, and two " \
                     "queries disagree.",
            instead: <<~RUBY,
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
          )
        end
      end
    end
  end
end
