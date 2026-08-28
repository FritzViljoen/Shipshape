# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Moments built without saying which zone they are in.
    #
    # **A point in time carries its zone. A calendar date does not.** `Time.now` takes
    # whatever offset the process happens to have — chosen by nobody, different on a
    # developer's laptop, a server and a background worker, and different again after a
    # deploy to another region. Nothing in the code records which one was meant, so nothing
    # can be wrong about it later and nothing can be checked.
    #
    # Two tiers, because they are different sizes of the same mistake:
    #
    # - **Unzoned** — `Time.now`, `Date.today`, `DateTime.parse`. The offset comes from the
    #   process. This is the one that produces a booking an hour out and a report that
    #   disagrees with the database.
    # - **One zone for everything** — `Time.current`, `Time.zone.now`. A configured zone,
    #   chosen once for the whole application. Correct far more often, and still an
    #   assumption rather than a statement: an application serving two countries has one
    #   zone in its config and two in its business.
    #
    # `Date.new` and `Date.parse` are NOT counted. A calendar date deliberately carries no
    # zone — a departure date, an invoice date — and converting one moves it a day.
    class TimesThatAssumeAZone
      TITLE = "Times built without naming a zone"
      LAW = "a-time-names-its-zone"
      WHY = "`Time.now` takes whatever offset the process has — different on a laptop, a " \
            "server and a worker — and nothing in the code records which was meant."
      CAVEAT = "A calendar date is not counted: `Date.new` and `Date.parse` carry no zone " \
               "on purpose, and converting one moves it a day. Nor can this see a zone " \
               "passed through a variable, so an application doing it properly through a " \
               "helper reads as silent here rather than as correct."
      NOUN = "moments built"
      SELF_RANKED = true

      # Whatever the process has.
      UNZONED = {
        "Time" => %i[now new at parse strptime iso8601 local],
        "DateTime" => %i[now parse strptime iso8601],
        "Date" => %i[today current],
      }.freeze

      # One zone, configured once, for the whole application.
      AMBIENT = {
        "Time" => %i[current zone],
        "DateTime" => %i[current],
      }.freeze

      def call(sources)
        sources.flat_map { |source| moments(source, UNZONED, "takes whatever offset the process has") }
               .concat(sources.flat_map { |source| moments(source, AMBIENT, "uses the one zone configured for the whole application") })
               .sort_by { |finding| finding.context[:tier] }
      end

      def population(sources)
        sources.sum { |source| all_moments(source).length }
      end

      def exemplars(sources)
        sources.flat_map { |source| named_zones(source) }
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil?

        <<~TEXT
          `#{finding.relative}:#{finding.line}` builds a moment without saying which zone it is in.

          The zone is an input, so it arrives like every other input — named by whoever knows
          it, which is the edge:

          ```ruby
          # in the action, where the requester's zone is known
          at = time_param!(:starts_at, time_zone: :time_zone)

          # in the operation, asserted like anything else
          def initialize(at:)
            @at = typed(at, ActiveSupport::TimeWithZone)
          end
          ```

          A bare `Time` or `DateTime` is then refused at the door rather than carried inward,
          and a string that states an offset disagreeing with the named zone bounces instead
          of one of the two answers being picked silently.
        TEXT
      end

      private

      def moments(source, table, why)
        found = []
        ClassReading.walk(source.ast) do |node|
          next unless node.send_type? && node.receiver && node.receiver.const_type?

          receiver = node.receiver.source
          next unless table[receiver]&.include?(node.method_name)

          found << Finding.new(
            relative: source.relative,
            line: node.loc.line,
            label: "#{receiver}.#{node.method_name} — #{why}",
            context: { tier: table.equal?(UNZONED) ? 0 : 1 },
          )
        end
        found
      end

      def all_moments(source)
        moments(source, UNZONED, "") + moments(source, AMBIENT, "") + named_zones(source)
      end

      # A zone said out loud — `Time.find_zone!("Africa/Johannesburg")`, `in_time_zone(zone)`.
      def named_zones(source)
        found = []
        ClassReading.walk(source.ast) do |node|
          next unless node.send_type?
          next unless %i[find_zone find_zone! in_time_zone].include?(node.method_name)
          next if node.arguments.empty?

          found << Finding.new(relative: source.relative, line: node.loc.line,
                               label: "#{node.method_name} — names the zone it means")
        end
        found
      end
    end
  end
end
