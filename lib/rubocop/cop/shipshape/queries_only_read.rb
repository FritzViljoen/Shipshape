# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-query-only-reads` (docs/laws/a-query-only-reads.md).
      #
      # **A query is one read.** It may reach a record — that is its whole job, and the call
      # matrix allows it — so `Shipshape/CallGraph` has nothing to say when the read turns out
      # to be a `create!`. The matrix governs *which kinds talk*, never *what they say*, and a
      # query writing through a record is the one defect that gap leaves open.
      #
      # It matters more than it looks. A query has no transaction, because a read needs none:
      # the generated `Query` deliberately opens nothing. So a write from inside one runs
      # outside any transaction this canon knows about, and a caller sequencing two queries
      # has no rollback for the second — while every name involved says nothing happened.
      #
      # WHAT IT DOES NOT CATCH: the write has to be rooted in a **record constant this
      # configuration resolves**. `PersonRecord.create!` and `PersonRecord.find(1).update!` are
      # seen; a write through a local, an ivar, or a value handed back by another object is
      # not — there is no constant to resolve and nothing that says what the receiver holds.
      # It reads method names, so a writer this list does not know is invisible, and a method
      # of the same name on something that is not a record is a false positive.
      # **Tests are exempt.**
      #
      # @example
      #   # bad
      #   class ListPeople < Query
      #     def call
      #       PersonRecord.create!(name: "x")
      #     end
      #   end
      #
      #   # good — the write is a command, and a workflow sequences the two
      #   class CreatePerson < Command
      #     def call
      #       success(PersonRecord.create!(name: @name))
      #     end
      #   end
      class QueriesOnlyRead < Base
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

        # **The constant a chain starts from.** `PersonRecord.find(1).update!` has a send for a
        # receiver, so looking only one hop back sees nothing and the commonest write of all
        # goes unreported.
        def root_constant(node)
          receiver = node.receiver

          while receiver&.send_type? || receiver&.csend_type?
            receiver = receiver.receiver
          end

          receiver&.const_type? ? receiver.source.sub(/\A::/, "") : nil
        end

        def record?(name)
          record_kinds.include?(kinds.for_constant(name))
        end

        def message_for(name, writer)
          explain(
            "`#{name}.#{writer}` is a write, and a query is one read.",
            because: "A query opens no transaction, because a read needs none — so this " \
                     "write runs outside any transaction, and a caller sequencing two " \
                     "queries has no rollback for the second. Every name on the path says " \
                     "nothing happened. The call graph cannot catch it: a query reaching a " \
                     "record is exactly what a query is for, so the matrix allows the call " \
                     "and only the message it sends is wrong.",
            instead: <<~RUBY,
              # the write is a command, with its own name and its own permission
              class CreatePerson < Command
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
          )
        end

        def writers
          @writers ||= cop_config.fetch("Writers", WRITERS.map(&:to_s)).map(&:to_sym)
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[query io_query legacy_query])
        end

        def record_kinds
          cop_config.fetch("RecordKinds", %w[record])
        end
      end
    end
  end
end
