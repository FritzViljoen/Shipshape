# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Methods on a record that only rearrange what the record already holds.
    class MethodsThatCouldMoveToAShape
      TITLE = "Rules that could move to a shape as they are"
      LAW = "persistence-holds-no-behaviour"
      WHY = "These only rearrange what the record already holds, so each one moves with no " \
            "new operation and no decision to make. The cheapest work in this report — and " \
            "the rest cannot move at all, because a shape has no database to reach."
      CAVEAT = "A heuristic, and an upper bound: it looks for database calls, other classes " \
               "and writes back to self. A method reaching another record through a plain " \
               "association reader is indistinguishable from one reading its own column, so " \
               "some of these will need an operation after all. Read before moving."
      NOUN = "rules on records"
      SHOW_SOURCE = false

      # Anything that leaves the object or changes it.
      REACHES = %i[
        exists? where find find_by find_each all first last count sum pluck order
        includes joins select group limit destroy destroy_all delete delete_all
        save save! update update! update_attribute update_column update_columns
        create create! new build touch increment! decrement! reload transaction lock
      ].freeze

      SUBJECT = "records under `app/models/`"

      def subjects(sources)
        sources.count { |source| source.relative.start_with?("app/models/") }
      end

      def call(sources)
        records(sources).flat_map do |source, node|
          ClassReading.public_methods_of(node).select { |method| movable?(method) }.map do |method|
            Finding.new(
              relative: source.relative,
              line: method.loc.line,
              label: "##{method.method_name} — reads only its own fields",
              context: { record: ClassReading.name_of(node), method: method.method_name },
            )
          end
        end
      end

      def population(sources)
        records(sources).sum { |_source, node| ClassReading.public_methods_of(node).length }
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil?

        <<~TEXT
          `#{finding.context[:record]}##{finding.context[:method]}` reads nothing but its own fields, so it moves to
          the shape unchanged:

          ```ruby
          class #{finding.context[:record]} < Shape
            def initialize(...)
              # the fields it already reads, asserted
            end

            def #{finding.context[:method]}
              # the body it has today, unchanged
            end
          end
          ```

          Nothing else has to move with it, and nothing calls it differently afterwards.

          **The rest cannot move, and that is the point rather than a shortfall.** A shape
          has no database, no associations and no reach, so a method needing any of those is
          impossible on one. It has two futures:

          - **A derived value becomes a field**, computed by the read that builds the shape
            while the database is already open. `auto_settled?` stops being a method and
            becomes `auto_settled:` — one read, at the moment everything else is read, rather
            than a read fired later by whoever happened to ask.
          - **A decision becomes an operation**, because a decision is a rule and a rule has
            one home.

          Neither is a Read class per derivation. That would be a class named
          `AutoSettledBooking`, and nobody would write it twice.
        TEXT
      end

      private

      BASES = [/\AApplicationRecord\z/, /\AActiveRecord::Base\z/, /Record\z/].freeze

      def records(sources)
        sources.select { |source| source.relative.start_with?("app/models/") }.flat_map do |source|
          ClassReading.classes(source).select { |node| record?(node) }.map { |node| [source, node] }
        end
      end

      def record?(node)
        superclass = ClassReading.superclass_of(node)
        return false if superclass.nil?

        BASES.any? { |pattern| pattern.match?(superclass) }
      end

      # Reads only what it holds: no other class named, no database call, no write to self.
      def movable?(method)
        body = method.body
        return false if body.nil?

        clean = true
        ClassReading.walk(body) do |node|
          clean = false if node.send_type? && node.receiver&.const_type?
          clean = false if node.send_type? && REACHES.include?(node.method_name)
          clean = false if %i[ivasgn op_asgn or_asgn and_asgn].include?(node.type)
          clean = false if node.send_type? && node.method_name.to_s.end_with?("=")
        end
        clean
      end
    end
  end
end
