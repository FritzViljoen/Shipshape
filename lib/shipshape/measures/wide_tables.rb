# frozen_string_literal: true

require "shipshape/source_text"
require "shipshape/measures/finding"

module Shipshape
  module Measures
    # The god object as it appears in the schema: one table, many columns.
    #
    # A class can be split quietly; a table cannot, which is why this is usually the last
    # thing to be fixed and the best single number for how far a codebase is from having a
    # domain. Every column past the point where the noun stops explaining them is a second
    # concept that had nowhere else to go.
    #
    # No threshold is applied. The widest tables are listed in order and the reader decides
    # — a number invented here would be arbitrary, and the shape of the list says more than
    # a line drawn across it.
    class WideTables
      TITLE = "Widest tables"
      LAW = "model-concerns-not-groups"
      WHY = "A class can be split quietly; a table cannot. Every column past the point " \
            "where the noun stops explaining them is a concept with nowhere else to go."
      CAVEAT = "No threshold — the widest are listed in order and the reader decides. A " \
               "line drawn here would be arbitrary."

      # Sorted widest-first in #call. Every finding is in db/schema.rb, so the report's
      # rank-by-file-frequency has nothing to order by and falls back to line number —
      # which put a 39-column table above a 145-column one.
      SELF_RANKED = true

      SCHEMA = "db/schema.rb"
      TABLE = /^\s*create_table\s+"([^"]+)"/.freeze
      COLUMN = /^\s*t\.\w+\s+"([^"]+)"/.freeze
      SHOWN = 10

      def initialize(root:)
        @root = root
      end

      def call(_sources)
        return [] unless File.file?(path)

        tables.sort_by { |_name, table| -table[:columns] }.first(SHOWN).map do |name, table|
          Finding.new(relative: SCHEMA, line: table[:line], label: "#{name} — #{table[:columns]} columns")
        end
      end

      private

      attr_reader :root

      def path
        File.join(root, SCHEMA)
      end

      def tables
        current = nil
        found = {}

        SourceText.lines(path).each_with_index do |line, index|
          if (match = TABLE.match(line))
            current = match[1]
            found[current] = { line: index + 1, columns: 0 }
          elsif current && COLUMN.match?(line)
            found[current][:columns] += 1
          end
        end

        found
      end
    end
  end
end
