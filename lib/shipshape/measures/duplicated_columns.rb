# frozen_string_literal: true

require "set"
require "shipshape/source_text"
require "shipshape/measures/finding"

module Shipshape
  module Measures
    # THE SAME FACT, STORED ON MORE THAN ONE TABLE (docs/decomposing/a-record-concern.md). A
    # lone recurring column means nothing either way, so a GROUP of columns recurring together
    # is counted instead — the full argument, and what it cannot see, is in WHY and CAVEAT.
    class DuplicatedColumns
      TITLE = "Columns duplicated across tables"
      LAW = "model-concerns-not-groups"
      WHY = "A concern shared by `include` obliges every includer's table independently, " \
            "because a model is a table and there is nowhere else to put a fact several " \
            "tables share — an address, a contact, a money amount, a slug. Nothing else " \
            "here catches it: every other guard reads one table, or one class, at a time, " \
            "and this is the only measure that compares tables against each other."
      CAVEAT = "Counts a group of two or more columns, matched on name and declared type, " \
               "only once it recurs on three or more tables — never a single column alone: " \
               "`id`, `name` and `created_at` recur on nearly every table and mean nothing " \
               "alone, while `supplier_email` and `contact_email` are almost certainly one " \
               "fact under two names and are invisible to a mechanical match either way. Two " \
               "tables sharing a group is left as coincidence — two authors reaching for the " \
               "same words the same week; three is where `RulesThatAreReallyData` draws its " \
               "own line, for the same reason. Every candidate is widened to the largest " \
               "column set recurring on that exact table set, so a five-column address " \
               "renders once, not as its ten pairs. `EXCLUDED_COLUMNS` is a declaration, not " \
               "a copy: being on it is what exempts a column, each entry states its own " \
               "reason, and none can go stale, because reality moving does not change what a " \
               "primary key or a timestamp is. Reads `db/schema.rb`, not `db/migrate/**` — " \
               "the same choice `NullableColumns` and `WideTables` make, because only the " \
               "flattened schema says which columns exist right now. Even a hit here is a " \
               "place to look, not a verdict: this narrows false positives, it does not " \
               "remove them."
      NOUN = "columns"

      SCHEMA = "db/schema.rb"
      TABLE = /^\s*create_table\s+"([^"]+)"/.freeze
      COLUMN = /^\s*t\.(\w+)\s+"([^"]+)"/.freeze

      EXCLUDED_COLUMNS = { # a declaration, not a copy — each entry is exempt for its own reason
        "id" => "the primary key, not a fact about the row",
        "created_at" => "when the row was written, not what it is about",
        "updated_at" => "when the row last changed, not what it is about",
        "lock_version" => "optimistic locking's own counter",
        "type" => "single-table inheritance's discriminator, not a domain value",
      }.freeze

      MINIMUM_TABLES = 3
      MINIMUM_GROUP_SIZE = 2

      SELF_RANKED = true # every finding is in db/schema.rb; WideTables sets this for the same reason

      def initialize(root:)
        @root = root
      end

      def population(_sources)
        return 0 unless File.file?(path)

        SourceText.lines(path).count { |line| COLUMN.match?(line) }
      end

      def call(_sources)
        return [] unless File.file?(path)

        found = tables
        maximal_groups(found)
          .sort_by { |columns, members| -(columns.size * members.size) }
          .map { |columns, members| finding_for(columns, members, found) }
      end

      # Distinct (table, column) lines implicated across every finding, not summed per finding
      # — the same column can be part of two overlapping groups (`email` is in both the auth
      # blob and the plain contact-info group on a real schema) and must not be paid for twice.
      def units(findings)
        findings.flat_map { |finding| finding.context[:tables].product(finding.context[:columns]) }.uniq.length
      end

      private

      attr_reader :root

      def path
        File.join(root, SCHEMA)
      end

      def tables # table name => { line:, columns: Set of "name:type" }
        current = nil
        found = {}

        SourceText.lines(path).each_with_index do |line, index|
          if (match = TABLE.match(line))
            current = match[1]
            found[current] = { line: index + 1, columns: Set.new }
          elsif current && (match = COLUMN.match(line))
            type, name = match[1], match[2]
            found[current][:columns] << "#{name}:#{type}" unless EXCLUDED_COLUMNS.key?(name)
          end
        end

        found
      end

      def candidate_groups(found) # membership is re-asked of every table below, not kept from here
        names = found.keys
        candidates = Set.new

        names.combination(2).each do |left, right|
          overlap = (found[left][:columns] & found[right][:columns]).sort
          candidates << overlap if overlap.size >= MINIMUM_GROUP_SIZE
        end

        candidates.to_a
      end

      def maximal_groups(found) # collapsed to the largest group per exact table set — see #superseded?
        supported = candidate_groups(found).filter_map do |columns|
          members = found.select { |_name, table| columns.all? { |c| table[:columns].include?(c) } }.keys.sort
          [columns, members] if members.size >= MINIMUM_TABLES
        end

        supported.group_by { |_columns, members| members }.flat_map do |members, group|
          columns_list = group.map(&:first)
          maximal = columns_list.reject { |candidate| superseded?(candidate, columns_list) }
          maximal.uniq.map { |columns| [columns, members] }
        end
      end

      def superseded?(candidate, columns_list)
        columns_list.any? { |other| other != candidate && (candidate - other).empty? && candidate.size < other.size }
      end

      def finding_for(columns, members, found)
        line = members.map { |name| found[name][:line] }.min
        names = columns.map { |entry| entry.split(":").first }.sort

        Finding.new(
          relative: SCHEMA, line: line,
          label: "#{names.join(', ')} — on #{members.size} tables: #{members.join(', ')}",
          context: { columns: names, tables: members },
        )
      end
    end
  end
end
