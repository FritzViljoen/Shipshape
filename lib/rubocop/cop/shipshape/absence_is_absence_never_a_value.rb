# frozen_string_literal: true

require "set"
require "shipshape/settings"
require "shipshape/source_text"
require "shipshape/measures/naming"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `absence-is-absence-never-a-value`.
      class AbsenceIsAbsenceNeverAValue < Base
        include Explains

        TABLE_FIRST = %i[
          add_column add_reference add_belongs_to
          change_column change_column_null change_column_default
        ].freeze

        TABLE_BLOCKS = %i[create_table change_table].freeze

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

        TABLE_NAME_ASSIGNMENT = /^\s*self\.table_name\s*=\s*(?:["']([^"']+)["']|:([a-zA-Z_]\w*))/.freeze

        MODULE_DECLARATION = /^\s*module\s+([\w:]+)\s*$/.freeze
        TABLE_NAME_PREFIX = /def\s+(?:self\.)?table_name_prefix\b.*?["']([^"']*)["'].*?\bend\b/m.freeze

        def on_new_investigation
          @promoted = []
          @table = nil
        end

        def on_def(node)
          @promoted = promotions_in(node)
        end

        def on_block(node)
          return unless TABLE_BLOCKS.include?(node.send_node.method_name)

          @table = name_of(node.send_node.first_argument)
        end

        def on_send(node)
          return if reversing?(node)
          return unless declares_a_column?(node)

          column = column_of(node)
          return if column.nil? || promoted?(column)

          table = table_of(node)
          return unless owned?(table)

          return if options_cannot_be_read?(node)

          nullable = null_option(node)
          return if nullable == false

          add_offense(nullable || node, message: message_for(table, column, nullable.nil?))
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

        # A nested column has no table of its own; the enclosing block tracked it above.
        def table_of(node)
          TABLE_FIRST.include?(node.method_name) ? name_of(node.arguments.first) : @table
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

        # A table nothing claims has not been reached by this canon yet; see the law's limit.
        def owned?(table)
          !table.nil? && owned_tables.include?(table)
        end

        def owned_tables
          @owned_tables ||= record_files.each_with_object(Set.new) do |path, tables|
            claimed = table_claimed_by(path)
            tables << claimed unless claimed.nil?
          end
        end

        def table_claimed_by(path)
          text = ::Shipshape::SourceText.read(path)
          match = text.match(TABLE_NAME_ASSIGNMENT)
          explicit = match && (match[1] || match[2])
          return explicit if explicit

          record = record_class_in(text, path)
          return nil if record.nil?

          default_table_name(qualified_name_of(record))
        end

        # Parsed, not read line by line: the nested form's `class` line names no module.
        def record_class_in(text, path)
          source = ::RuboCop::ProcessedSource.new(text, RUBY_VERSION.to_f, path)
          return nil unless source.valid_syntax? && source.ast

          candidate = [source.ast, *source.ast.each_descendant].find(&:class_type?)
          return nil if candidate.nil?

          superclass = candidate.children[1]&.source
          return nil unless record_base_classes.include?(superclass)

          candidate
        end

        # Compact carries its module in the class node's own name; nested, in its ancestors.
        def qualified_name_of(class_node)
          enclosing = class_node.each_ancestor(:module, :class).map { |node| node.children.first.source }
          (enclosing.reverse + [class_node.children.first.source]).join("::")
        end

        # Crude on purpose like `Measures::Naming` — see the law for what it still misses.
        def default_table_name(class_name)
          segments = class_name.split("::")
          simple = segments.pop
          undecorated = ::Shipshape::Measures::Naming.plural(::Shipshape::Measures::Naming.snake(simple))

          "#{owning_prefix(segments)}#{undecorated}"
        end

        def owning_prefix(segments)
          segments.length.downto(1) do |depth|
            prefix = table_name_prefixes[segments.first(depth).join("::")]
            return prefix if prefix
          end
          nil
        end

        # A file's prefix counts only if it is the file's one module and a literal — see the law.
        def table_name_prefixes
          @table_name_prefixes ||= prefix_source_files.each_with_object({}) do |path, prefixes|
            text = ::Shipshape::SourceText.read(path)
            modules = text.scan(MODULE_DECLARATION).flatten.uniq
            next unless modules.one?

            literal = text[TABLE_NAME_PREFIX, 1]
            prefixes[modules.first] = literal if literal
          end
        end

        # `app` and `lib`: a prefix module is not always under the `record` kind's own paths.
        def prefix_source_files
          %w[app lib].flat_map { |root| Dir.glob(File.join(base_dir, root, "**", "*.rb")) }.uniq
        end

        def record_files
          owner_kinds.flat_map { |kind| settings.kinds.fetch(kind, []) }
                     .flat_map { |glob| Dir.glob(File.join(base_dir, glob)) }
                     .uniq
        end

        def record_base_classes
          @record_base_classes ||= owner_kinds.flat_map { |kind| settings.base_classes.fetch(kind, []) }
        end

        def owner_kinds
          cop_config.fetch("Kinds", %w[record])
        end

        def settings
          @settings ||= ::Shipshape::Settings.layout(config)
        end

        # From the configuration that loaded this cop, never `Dir.pwd`: resolving from the
        # working directory silently matches nothing when RuboCop runs in a subdirectory.
        def base_dir
          config.base_dir_for_path_parameters
        end

        def message_for(table, column, silent)
          said = silent ? "says nothing about `null:`, which means nullable" : "is nullable"

          explain(
            "`#{table}.#{column}` #{said}, so every row that holds no value holds the same " \
            "unreadable one.",
            because: "A null is not \"off\", not \"inherit\", not \"not applicable\", not " \
                     "\"we lost it\" — it is all of them at once, and no reader can tell " \
                     "which. Every meaning given to it is a fact nobody declared, so the " \
                     "meaning lives in whichever question happens to be reading, and two " \
                     "questions disagree.",
            instead: NOT_NULL,
          )
        end
      end
    end
  end
end
