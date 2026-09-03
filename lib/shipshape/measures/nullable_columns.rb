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
      COLUMN = /^\s*t\.(\w+)\s+"([^"]+)"(.*)$/.freeze
      TIMESTAMPS = %w[created_at updated_at].freeze

      def initialize(root:)
        @root = root
      end

      # Takes the parsed sources like every other measure and ignores them: the schema is
      # not under `app/`. Same shape in, so the report needs no special case.
      def call(_sources)
        return [] unless File.file?(path)

        SourceText.lines(path).each_with_index.flat_map { |line, index| finding(line, index + 1) }.compact
      end

      private

      attr_reader :root

      def path
        File.join(root, SCHEMA)
      end

      def finding(line, number)
        match = COLUMN.match(line)
        return nil if match.nil?

        name = match[2]
        return nil if TIMESTAMPS.include?(name)

        trailing = match[3]
        return Finding.new(relative: SCHEMA, line: number, label: "#{name} — has a default") if trailing.include?("default:")
        return nil if trailing.include?("null: false")

        Finding.new(relative: SCHEMA, line: number, label: "#{name} — nullable")
      end
    end
  end
end
