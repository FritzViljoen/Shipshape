# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-read-writes-nothing`.
      class ReadsWriteNothing < Base
        include ReadsKinds

        # Every one of these writes. Deliberately a closed list rather than a pattern: `save`
        # and `destroy` share no shape, and a pattern loose enough for both catches `saved?`.
        WRITERS = %i[
          create create! update update! update_all update_column update_columns
          save save! destroy destroy! destroy_all delete delete_all
          insert insert_all upsert upsert_all touch
          increment! decrement! toggle!
          first_or_create first_or_create! find_or_create_by find_or_create_by!
        ].freeze

        WRITE = <<~RUBY
          # the write is a write, with its own name and its own permission
          class CreatePerson < Write
            def call
              success(PersonRecord.create!(name: @name))
            end
          end

          # needed both? that is a workflow, which is what accepts the bill for
          # spanning two transactions
          class RegisterPerson < Workflow
            def call
              found = FindPerson.call(actor: actor, email: @email)
              return found if found.value

              CreatePerson.call(actor: actor, email: @email)
            end
          end
        RUBY

        def on_send(node)
          return unless writers.include?(node.method_name)
          return unless one_of?(governed_kinds)

          name = root_constant(node)
          return if name.nil?
          return unless record?(name)

          add_offense(node.loc.selector, message: message_for(name, node.method_name))
        end

        alias on_csend on_send

        private

        def message_for(name, writer)
          explain(
            "`#{name}.#{writer}` is a write, and a read performs no write.",
            because: "A read opens no transaction, because a read needs none — so this " \
                     "write runs outside any transaction, and a caller sequencing two " \
                     "reads has no rollback for the second. Every name on the path says " \
                     "nothing happened. The call graph cannot catch it: a read reaching a " \
                     "record is exactly what a read is for, so the matrix allows the call " \
                     "and only the message it sends is wrong.",
            instead: WRITE,
          )
        end

        def writers
          @writers ||= cop_config.fetch("Writers", WRITERS.map(&:to_s)).map(&:to_sym)
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[read io_read legacy_read])
        end
      end
    end
  end
end
