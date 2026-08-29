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
      # **A column may be nullable between two statements of one migration method.** A NOT
      # NULL column cannot be added to a populated table in one statement, so it is added
      # nullable, filled, and promoted — and the promotion comes later in the same method.
      # The cop holds that rule: a nullable column promoted in the same method passes.
      #
      # WHAT IT DOES NOT CATCH: it reads **migrations, not the live schema**. A column made
      # nullable by a hand-run statement, a tool or a vendored migration is invisible, so a
      # passing run proves what this repo's migrations did, not what the database holds.
      #
      # @example
      #   # bad
      #   t.string :nickname, null: true
      #   add_column :people, :nickname, :string, null: true
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

        ADDERS = %i[add_column add_reference add_belongs_to].freeze
        REVERSING = %i[down remove_column remove_reference].freeze

        def on_def(node)
          @promoted = promotions_in(node)
        end

        # `t.string :nickname, null: true` and `add_column ..., null: true`.
        def on_send(node)
          return if reversing?(node)

          nullable = null_option(node)
          return unless nullable
          return if promoted?(node)

          add_offense(nullable, message: message_for(column_of(node)))
        end

        private

        def null_option(node)
          options = node.arguments.last
          return unless options.respond_to?(:hash_type?) && options.hash_type?

          pair = options.pairs.find { |candidate| candidate.key.value == :null }
          pair if pair&.value&.true_type?
        end

        # `change_column_null :people, :nickname, false` — the promotion this method makes.
        def promotions_in(definition)
          return [] unless definition.body

          definition.body.each_node(:send).select do |send|
            send.method_name == :change_column_null && send.arguments.size >= 3 &&
              send.arguments[2].false_type?
          end.map { |send| send.arguments[1].value.to_s }
        end

        def promoted?(node)
          Array(@promoted).include?(column_of(node))
        end

        def column_of(node)
          argument = ADDERS.include?(node.method_name) ? node.arguments[1] : node.arguments.first
          argument.respond_to?(:value) ? argument.value.to_s : argument.source
        end

        # Dropping a column, or the `down` half, is the reverse direction and exempt.
        def reversing?(node)
          REVERSING.include?(node.method_name) ||
            node.each_ancestor(:def).any? { |definition| definition.method?(:down) }
        end

        def message_for(column)
          explain(
            "`#{column}` is nullable, so every row that holds no value holds the same " \
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
