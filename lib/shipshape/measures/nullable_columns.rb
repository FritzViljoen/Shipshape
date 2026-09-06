# frozen_string_literal: true

require "shipshape/source_text"
require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Nullable columns and database defaults, read from `db/schema.rb`.
    class NullableColumns
      TITLE = "Nullable columns and database defaults"
      LAW = "absence-is-absence-never-a-value"
      WHY = "A nullable column is a gap given a meaning nobody declared; a default is a " \
            "second place deciding a value."

      NOUN = "columns"

      def population(_sources)
        return 0 unless File.file?(path)

        SourceText.lines(path).count { |line| COLUMN.match?(line) }
      end

      SCHEMA = "db/schema.rb"
      TABLE = /^\s*create_table\s+"([^"]+)"/.freeze
      COLUMN = /^\s*t\.(\w+)\s+"([^"]+)"(.*)$/.freeze
      TIMESTAMPS = %w[created_at updated_at].freeze

      def initialize(root:)
        @root = root
      end

      # Takes the parsed sources like every other measure and ignores them: the schema is
      # not under `app/`. Same shape in, so the report needs no special case.
      def call(_sources)
        return [] unless File.file?(path)

        table = nil
        SourceText.lines(path).each_with_index.filter_map do |line, index|
          match = TABLE.match(line)
          table = match[1] if match
          finding(line, index + 1, table)
        end
      end

      # One column at a time is what this measure sees, so a cluster of nullable columns
      # each reads as its own small problem — the proposal asks that question first.
      def proposal(findings)
        finding = findings.find { |candidate| candidate.label.end_with?("— nullable") }
        return nil if finding.nil?

        table = finding.context && finding.context[:table]
        named = table ? "`#{table}`" : "its table"

        <<~TEXT
          `#{finding.relative}:#{finding.line}` is one column, but this measure reads one
          column at a time — ten nullable columns on #{named} read as ten small problems,
          and fixing each with its own join builds ten satellites for a table that shrank
          by nothing.

          Before deciding what this column needs, check whether it has siblings that move
          together as one concern:

          ```sh
          shipshape tables --table #{table || "<table>"}
          ```

          Columns present or absent on the same rows are one concern and get one table, not
          one join each:

          ```ruby
          create_table "cancellations" do |t|
            t.references :booking, null: false, foreign_key: true, index: {unique: true}
            t.string     :reason, null: false
            t.timestamps
          end
          ```

          A column that truly stands alone still gets the plain answer: `null: false` if it
          can be backfilled, a join with a unique index if the row itself is what is missing.
        TEXT
      end

      private

      attr_reader :root

      def path
        File.join(root, SCHEMA)
      end

      def finding(line, number, table)
        match = COLUMN.match(line)
        return nil if match.nil?

        name = match[2]
        return nil if TIMESTAMPS.include?(name)

        context = table ? { table: table } : nil
        trailing = match[3]
        if trailing.include?("default:")
          return Finding.new(relative: SCHEMA, line: number, label: "#{name} — has a default", context: context)
        end
        return nil if trailing.include?("null: false")

        Finding.new(relative: SCHEMA, line: number, label: "#{name} — nullable", context: context)
      end
    end
  end
end
