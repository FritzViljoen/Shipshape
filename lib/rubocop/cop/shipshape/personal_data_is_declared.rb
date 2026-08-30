# frozen_string_literal: true

require "shipshape/source_text"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `personal-data-is-declared-and-erasable`
      # (docs/laws/personal-data-is-declared-and-erasable.md).
      #
      # **The right to erasure is unimplementable without an inventory.** Not difficult —
      # unimplementable. You cannot delete what nobody can enumerate, and in a schema of two
      # hundred tables nobody enumerates it from memory. Every request becomes fresh
      # archaeology, answered by whoever is on duty, differently each time.
      #
      # So this reads the schema, and for every column whose name suggests a person it asks
      # `app/shipshape/personal_data.rb` what happens to that column on erasure. A column
      # nobody has classified is the offence. **`:not_personal` is one of the four answers** —
      # the point is that somebody decided, once, while they still remembered.
      #
      # **THIS IS NOT A COMPLIANCE CHECK AND MUST NEVER BE DESCRIBED AS ONE.** It says where
      # data is and what was decided about it. It says nothing about whether you had a lawful
      # basis to collect it, whether the retention is justified, or whether an anonymisation
      # is irreversible in fact. Those are judgements, and a green build that somebody reads
      # as legal assurance is worse than no check at all.
      #
      # **A repository whose schema is `structure.sql` gets nothing from this, silently.**
      # Discourse is one, and it reported zero — which is indistinguishable from a clean
      # schema. The installed `personal_data_is_erasable_test.rb` asks the connection instead
      # and does not care how the schema is stored, which is the answer for those repositories.
      #
      # WHAT IT DOES NOT CATCH: it matches **column names**, so `contact_ref`, `handle`, and
      # every field named for the business rather than for the person are invisible until
      # added to `Names`. It reads `db/schema.rb`, so a column created by a hand-run statement
      # or by another service sharing the database is not there — the installed
      # `personal_data_is_erasable_test.rb` asks the connection instead, which is the stronger
      # question. And **most personal data is not in a database at all**: logs, backups,
      # analytics, a warehouse, a third party's store. A repository-scoped tool sees a
      # fraction, and this one does not know what fraction.
      #
      # @example
      #   # bad — the schema has it and nothing says what happens to it
      #   create_table "users" do |t|
      #     t.string "email"
      #   end
      #
      #   # good — app/shipshape/personal_data.rb
      #   COLUMNS = { "users" => { "email" => :anonymise } }.freeze
      class PersonalDataIsDeclared < Base
        include Explains

        # The list is the fact. A name not here is not "permitted" — it is unexamined, which
        # is why the law says so in as many words rather than leaving it to be discovered.
        NAMES = %w[
          email phone mobile telephone address postcode zipcode ip_address
          first_name last_name full_name surname forename maiden_name
          date_of_birth dob birth_date passport national_id ssn nino tax_id
          latitude longitude gender nationality signature avatar photo
        ].freeze

        REGISTRY = "app/shipshape/personal_data.rb"

        # Blocks whose body declares columns on one named table.
        TABLE_BLOCKS = %i[create_table change_table].freeze

        def on_new_investigation
          @table = nil
        end

        # `create_table "users" do |t|` — everything inside belongs to that table, and so does
        # everything inside a `change_table`. Reading only `create_table` left `@table` holding
        # the previous one, so a `change_table "leads"` had its columns judged against `users` —
        # the cross-table blindness this cop was fixed to remove, one block type over.
        #
        # Any other block clears it, so a column reached through something unrecognised is
        # attributed to no table rather than to whichever came last.
        def on_block(node)
          @table = table_of(node.send_node)
        end

        def table_of(send_node)
          return nil unless TABLE_BLOCKS.include?(send_node.method_name)

          literal(send_node.first_argument)
        end

        def on_send(node)
          @table = literal(node.first_argument) if node.method?(:add_column)
          column = column_of(node)
          return if column.nil?
          return unless personal?(column)
          return if declared?(@table.to_s, column)

          add_offense(node, message: message_for(column))
        end

        private

        # `t.string "email"` inside a create_table block, and `add_column "users", "email"`
        # outside one. Only the column name is needed — the table is context.
        def column_of(node)
          return nil if holds_a_flag?(node)
          return literal(node.arguments[1]) if node.method?(:add_column)
          return nil unless node.receiver&.lvar_type?

          literal(node.first_argument)
        end

        # **A boolean cannot hold a person.** `is_from_email` and `show_email` both end in a
        # name on the list and are flags — found by running this against two real schemas,
        # where they were two of six findings. Asking somebody to classify a boolean as
        # `:not_personal` is a guard firing on correct code, which is not strict but wrong.
        def holds_a_flag?(node)
          return node.method?(:boolean) if node.receiver&.lvar_type?
          return false unless node.method?(:add_column)

          type = node.arguments[2]
          type.respond_to?(:value) && type.value.to_s == "boolean"
        end

        def literal(node)
          return nil unless node.respond_to?(:type)

          node.str_type? || node.sym_type? ? node.value.to_s : nil
        end

        def personal?(column)
          names.any? { |name| column == name || column.end_with?("_#{name}") }
        end

        # **Parsed, not text-matched**, and per table.
        #
        # Matching the file as text failed twice over. The registry `shipshape install` writes
        # carries commented-out examples, so a fresh install was already blind to `email` and
        # `ip_address` while `COLUMNS` was genuinely empty — and any prose did it, so a
        # `# TODO: decide about "passport"` cleared `passport`. And the column was matched
        # without its table, so classifying `users.email` cleared `email` on every other table
        # in the schema. Both were green builds over exactly what this exists to catch.
        def declared?(table, column)
          registry.fetch(table, []).include?(column)
        end

        # table => [column, …], read from the `COLUMNS` literal. A computed entry is invisible,
        # which is why the template says to write it flat, and which the law states as a limit.
        def registry
          @registry ||= parse(registry_path)
        end

        def registry_path
          File.join(base_dir, cop_config.fetch("Registry", REGISTRY))
        end

        def parse(path)
          return {} unless File.file?(path)

          source = RuboCop::ProcessedSource.new(::Shipshape::SourceText.read(path), RUBY_VERSION.to_f, path)
          literal = source.ast&.each_descendant(:casgn)&.find { |node| node.name == :COLUMNS }

          literal.nil? ? {} : tables(literal)
        end

        def tables(assignment)
          hash = assignment.each_descendant(:hash).first
          return {} if hash.nil?

          hash.pairs.to_h { |pair| [text(pair.key), columns_of(pair.value)] }
        end

        def columns_of(node)
          inner = node.hash_type? ? node : node.each_descendant(:hash).first
          return [] if inner.nil?

          inner.pairs.map { |pair| text(pair.key) }.compact
        end

        def text(node)
          node.respond_to?(:value) ? node.value.to_s : nil
        end

        def message_for(column)
          explain(
            "`#{column}` looks like it holds something about a person, and nothing says what " \
            "happens to it when that person asks to be forgotten.",
            because: "Erasure is unimplementable without an inventory — you cannot delete " \
                     "what nobody can enumerate, and nobody enumerates two hundred tables " \
                     "from memory. Every request then becomes archaeology, answered by " \
                     "whoever is on duty and differently each time. The decision is cheap " \
                     "now, while whoever added the column still remembers what it holds, " \
                     "and expensive on the day somebody asks.",
            instead: <<~RUBY,
              # app/shipshape/personal_data.rb — one line, four possible answers
              COLUMNS = {
                "users" => {
                  "#{column}" => :anonymise,       # overwritten, row stays
                  # or :delete_row          the row goes
                  # or :retain_with_reason  it stays, and the reason is written here
                  # or :not_personal        it matched the name and is not about a person
                },
              }.freeze
            RUBY
          )
        end

        def names
          @names ||= cop_config.fetch("Names", NAMES)
        end

        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
