# frozen_string_literal: true

require "shipshape/source_text"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `personal-data-is-declared-and-erasable`.
      class PersonalDataIsDeclared < Base
        include Explains

        # The list is the fact: a name not here is unexamined, not permitted.
        NAMES = %w[
          email phone mobile telephone address postcode zipcode ip_address
          first_name last_name full_name surname forename maiden_name
          date_of_birth dob birth_date passport national_id ssn nino tax_id
          latitude longitude gender nationality signature avatar photo
        ].freeze

        REGISTRY = "app/shipshape/personal_data.rb"

        TABLE_BLOCKS = %i[create_table change_table].freeze

        def on_new_investigation
          @table = nil
        end

        # `change_table` too: reading only `create_table` left `@table` holding the previous
        # one, so a `change_table "leads"` had its columns judged against `users`. Any other
        # block clears it, so an unrecognised one attributes to no table rather than the last.
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

        def column_of(node)
          return nil if holds_a_flag?(node)
          return literal(node.arguments[1]) if node.method?(:add_column)
          return nil unless node.receiver&.lvar_type?

          literal(node.first_argument)
        end

        # A boolean cannot hold a person: `is_from_email` and `show_email` end in a listed name
        # and are flags. Two of six findings on the two real schemas this was run against.
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

        # Parsed, not text-matched, and per table. Text matching read the registry's own
        # commented-out examples as declarations, and matched a column without its table — so
        # classifying `users.email` cleared `email` everywhere. Both were green over the gap.
        def declared?(table, column)
          registry.fetch(table, []).include?(column)
        end

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
