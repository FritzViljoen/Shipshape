# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Methods on a record that only rearrange what the record already holds.
    #
    # **This is the extraction list, not a complaint.** Every method here can move to the
    # shape as it stands — no new operation, no new file, no decision to make. It is the
    # cheapest work in the report and the first thing to do on any record being split.
    #
    # The test is one question: **does the method need anything it was not handed?**
    #
    # It is not a matter of taste. A shape holds values and has no database, no
    # associations and no reach — so a method needing any of those **cannot exist on one**.
    # The question is not where it would be tidier; it is whether it is possible.
    #
    #     def activity_date
    #       booking_date.to_date            # its own field, rearranged — moves
    #     end
    #
    #     def auto_settled?
    #       commission_transfers.exists?    # a database query — stays, becomes a Query
    #     end
    #
    #     def start_time
    #       self[:start_time] ||= inventory.start_at_on_date(booking_date)
    #     end                               # reads another record AND writes back — stays
    #
    # That last one is why the question has to be asked mechanically rather than by eye. It
    # reads like an accessor, reaches into another record, and mutates the row on the way
    # past — invisible on a record, impossible on a shape.
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

          - **A derived value becomes a field**, computed by the query that builds the shape
            while the database is already open. `auto_settled?` stops being a method and
            becomes `auto_settled:` — one read, at the moment everything else is read, rather
            than a query fired later by whoever happened to ask.
          - **A decision becomes an operation**, because a decision is a rule and a rule has
            one home.

          Neither is a Query class per derivation. That would be a class named
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
