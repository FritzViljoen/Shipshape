# frozen_string_literal: true

require "shipshape/source_text"
require "shipshape/typed_arguments"

module Shipshape
  # One table, every column read together: is this a concept, or two wearing one name. Evidence
  # only — no verdict, no score, no threshold; the caller decides what a nullable column, a
  # flag cluster, a status pair and a satellite table mean together.
  class TableShapes
    include TypedArguments

    SCHEMA = "db/schema.rb"

    Column = Struct.new(:name, :type, :nullable, :default, keyword_init: true)

    # `shape` is what the extraction bought, without reading a row: `unique` false is an
    # ordinary one-to-many; `nil` means neither named unique-key pattern matched, reported
    # as raw counts in `other_columns` rather than forced into one.
    Neighbour = Struct.new(:table, :column, :unique, :shape, :other_columns, keyword_init: true)

    Table = Struct.new(:name, :columns, :neighbours, :declared, keyword_init: true) do
      def column_count
        columns.length
      end

      def nullable
        columns.select(&:nullable).map(&:name)
      end

      # `NoNullableColumns` reads migrations, not this schema — a column none of them declares
      # (predating adoption, or left by a squash) is invisible to it, clean report or not.
      def migration_blind
        nullable - declared
      end

      def booleans
        columns.select { |column| column.type == "boolean" }.map(&:name)
      end

      def status_shaped
        columns.select { |column| STATUS_TYPES.include?(column.type) && STATUS_NAME.match?(column.name) }
               .map(&:name)
      end

      # NOT NULL closes the null escape route; "" or a default reopens it under a different
      # name. Named here because it is otherwise invisible: the column reads as fixed.
      def blank_sentinel_capable
        columns.reject { |column| column.nullable || TIMESTAMPS.include?(column.name) }
               .select { |column| BLANKABLE_TYPES.include?(column.type) }
      end
    end

    STATUS_TYPES = %w[string integer].freeze
    BLANKABLE_TYPES = %w[string text].freeze
    STATUS_NAME = /(?:\A|_)(state|status|kind|type)\z/.freeze
    TIMESTAMPS = %w[created_at updated_at].freeze

    TABLE = /^\s*create_table\s+"([^"]+)"(.*)$/.freeze
    COLUMN = /^\s*t\.(\w+)\s+"([^"]+)"(.*)$/.freeze
    INLINE_INDEX = /^\s*t\.index\s+(\[[^\]]*\])(.*)$/.freeze
    ADD_INDEX = /^\s*add_index\s+"([^"]+)"\s*,\s*(\[[^\]]*\])(.*)$/.freeze
    ADD_FOREIGN_KEY = /^\s*add_foreign_key\s+"([^"]+)"\s*,\s*"([^"]+)"(.*)$/.freeze
    PRIMARY_KEY = /primary_key:\s*"([^"]+)"/.freeze
    DEFAULT = /default:\s*([^,\n]+)/.freeze
    COLUMN_NAME = /"([^"]+)"/.freeze

    MIGRATIONS = "db/migrate/*.rb"

    def initialize(root:)
      @root = typed(root, String)
    end

    def call
      return [] unless File.file?(path)

      lines = SourceText.lines(path)
      columns_by_table, primary_keys = read_tables(lines)
      unique_by_table = read_unique_columns(lines, primary_keys)
      neighbours_by_parent = read_neighbours(lines, unique_by_table, columns_by_table)
      declared_by_table = read_migrations

      columns_by_table.map do |name, columns|
        Table.new(
          name: name, columns: columns, neighbours: neighbours_by_parent.fetch(name, []),
          declared: declared_by_table.fetch(name, []),
        )
      end
    end

    def migrations_scanned
      Dir.glob(File.join(root, MIGRATIONS)).length
    end

    private

    attr_reader :root

    def path
      File.join(root, SCHEMA)
    end

    def read_tables(lines)
      columns = {}
      primary_keys = {}
      current = nil

      lines.each do |line|
        table = TABLE.match(line)
        if table
          current = table[1]
          columns[current] = []
          primary_keys[current] = table[2][PRIMARY_KEY, 1]
          next
        end

        column = current && COLUMN.match(line)
        columns[current] << column_from(column) if column
      end

      [columns, primary_keys]
    end

    def column_from(match)
      type = match[1]
      name = match[2]
      trailing = match[3]

      Column.new(
        name: name,
        type: type,
        nullable: !TIMESTAMPS.include?(name) && !trailing.include?("null: false"),
        default: trailing[DEFAULT, 1],
      )
    end

    # A single-column unique index, an `add_index`, or a custom primary key: three spellings
    # of one fact, that this column alone answers "which row is this".
    def read_unique_columns(lines, primary_keys)
      unique = Hash.new { |hash, key| hash[key] = [] }
      current = nil

      primary_keys.each { |table, key| unique[table] << key if key }

      lines.each do |line|
        table = TABLE.match(line)
        current = table[1] if table

        add_unique(unique, current, line) if current
        add_top_level_unique(unique, line)
      end

      unique
    end

    def add_unique(unique, table, line)
      inline = INLINE_INDEX.match(line)
      return unless inline && inline[2].include?("unique: true")

      names = names_in(inline[1])
      unique[table] << names.first if names.length == 1
    end

    def add_top_level_unique(unique, line)
      top_level = ADD_INDEX.match(line)
      return unless top_level && top_level[3].include?("unique: true")

      names = names_in(top_level[2])
      unique[top_level[1]] << names.first if names.length == 1
    end

    def names_in(bracket)
      bracket.scan(COLUMN_NAME).flatten
    end

    NOT_A_FACT = (TIMESTAMPS + ["id"]).freeze

    def read_neighbours(lines, unique_by_table, columns_by_table)
      neighbours = Hash.new { |hash, key| hash[key] = [] }

      lines.each do |line|
        match = ADD_FOREIGN_KEY.match(line)
        next unless match

        child = match[1]
        parent = match[2]
        column = match[3][/column:\s*"([^"]+)"/, 1] || default_fk_column(parent)
        unique = unique_by_table.fetch(child, []).include?(column)
        others = other_columns(columns_by_table.fetch(child, []), column)

        neighbours[parent] << Neighbour.new(
          table: child, column: column, unique: unique,
          shape: shape_of(unique, others), other_columns: others.map(&:name),
        )
      end

      neighbours
    end

    def other_columns(columns, fk_column)
      columns.reject { |column| column.name == fk_column || NOT_A_FACT.include?(column.name) }
    end

    # `unique` false is an ordinary one-to-many. `unique` true splits on the columns beside the
    # key: 2+ NOT NULL is several facts together; one NOT NULL is the sanctioned fix — absence
    # is the row, not a null; one nullable is that same column, moved but still nullable.
    def shape_of(unique, others)
      return :unlocked_cardinality unless unique
      return :unlocked_composite_fact if others.reject(&:nullable).length >= 2
      return :unlocked_absence if others.length == 1 && !others.first.nullable
      return :unlocked_nothing if others.length == 1 && others.first.nullable

      nil
    end

    MIGRATION_TABLE_FIRST =
      /\b(add_column|add_reference|add_belongs_to|change_column|change_column_null|change_column_default)\s*\(?\s*:(\w+)\s*,\s*:(\w+)/.freeze
    MIGRATION_BLOCK = /\b(?:create_table|change_table)\s*\(?\s*:(\w+).*do\s*\|\s*(\w+)\s*\|/.freeze
    MIGRATION_COLUMN = /^\s*(\w+)\.(\w+)(?:\s+:(\w+))?/.freeze
    REFERENCE_METHODS = %w[references belongs_to add_reference add_belongs_to].freeze
    NOT_A_COLUMN_METHOD = %w[index foreign_key check_constraint timestamps].freeze

    # `add_reference :orders, :customer` adds `customer_id`, not `customer` — no inflection
    # needed, the column is always the given name plus `_id`.
    def migration_column_name(method, name)
      REFERENCE_METHODS.include?(method) ? "#{name}_id" : name
    end

    def read_migrations
      declared = Hash.new { |hash, key| hash[key] = [] }
      Dir.glob(File.join(root, MIGRATIONS)).sort.each { |file| scan_migration(SourceText.lines(file), declared) }
      declared
    end

    def scan_migration(lines, declared)
      table = nil
      var = nil

      lines.each do |line|
        single = MIGRATION_TABLE_FIRST.match(line)
        declared[single[2]] << migration_column_name(single[1], single[3]) if single

        block = MIGRATION_BLOCK.match(line)
        table, var = block[1], block[2] if block
        next if block

        column = table && MIGRATION_COLUMN.match(line)
        next unless column && column[1] == var && column[3] && !NOT_A_COLUMN_METHOD.include?(column[2])

        declared[table] << migration_column_name(column[2], column[3])
      end
    end

    # Only reached when the schema omits `column:`, which Rails does exactly when the column
    # already matches this default — so a wrong guess here never overrides a stated one.
    def default_fk_column(table)
      "#{singularize(table)}_id"
    end

    def singularize(word)
      return word.sub(/ies\z/, "y") if word.end_with?("ies")
      return word.sub(/es\z/, "") if word.end_with?("sses", "xes", "ches", "shes")
      return word.sub(/s\z/, "") if word.end_with?("s")

      word
    end
  end
end
