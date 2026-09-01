# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the entering half of `nothing-travels-off-the-call-path`, and the ambient-zone
      # half of `a-time-names-its-zone`.
      class NoAmbientReads < Base
        include ReadsKinds

        # Each entry is `receiver => methods`, and each is a dependency arriving off the
        # call path. Closed, and the law says so.
        CLOCKS = {
          "Time" => %i[now current],
          "Date" => %i[today current yesterday tomorrow],
          "DateTime" => %i[now current],
          "Time.zone" => %i[now today],
        }.freeze

        # Each of these builds a moment in whatever zone the process happens to have, so the
        # zone is read without being named. `Date.parse` and `Date.new` are deliberately
        # absent: a calendar date carries no zone by design, so building one reads nothing
        # ambient. `DateTime.new` is absent for the same reason — Ruby gives it a stated
        # offset. `Time.new` is not: with arguments or without, it lands in the local zone.
        NAIVE_BUILDERS = {
          "Time" => %i[parse strptime iso8601 at new],
          "DateTime" => %i[parse strptime iso8601],
        }.freeze

        # A bare cast builds its result in the process's local zone. `to_date` is absent for
        # the same reason `Date.parse` is.
        NAIVE_CASTS = %i[to_time to_datetime].freeze

        AMBIENT_CONSTANTS = %w[ENV Thread Current RequestStore].freeze

        ZONE_READS = %i[zone zone_default].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)

          reason = clock(node) || builder(node) || cast(node) || ambient(node) || zone(node)
          return unless reason

          add_offense(node, message: reason)
        end

        # `$global` and `Thread.current[:key]` reach the same way.
        def on_gvar(node)
          return unless one_of?(governed_kinds)

          add_offense(node, message: message_for(node.source, "a global"))
        end

        private

        def clock(node)
          receiver = node.receiver&.source
          return unless CLOCKS.fetch(receiver, []).include?(node.method_name)

          explain(
            "`#{node.source}` reads the clock, and nothing at the call site chose it.",
            because: "The current time is a dependency that is not on the call path: the " \
                     "caller cannot see it, a test cannot set it without reaching around " \
                     "the object, and the value differs on every run. The caller knows " \
                     "when it is running. The operation does not, and must not guess. " \
                     "A bare `Time.now` also carries whatever offset the process had, " \
                     "chosen by nobody.",
            instead: MOMENT,
          )
        end

        # Parsing at all is `input-is-parsed-at-the-seam`'s business. What this reports is the
        # narrower fact that these spellings take their zone from the process.
        def builder(node)
          return unless NAIVE_BUILDERS.fetch(node.receiver&.source, []).include?(node.method_name)

          placed_by_nobody(node.source)
        end

        def cast(node)
          return unless NAIVE_CASTS.include?(node.method_name)
          return if node.receiver.nil? || node.arguments.any?

          placed_by_nobody(node.source)
        end

        def placed_by_nobody(source)
          explain(
            "`#{source}` builds a moment in whatever zone the process happens to have.",
            because: "The zone is a dependency that is not on the call path: nothing at the " \
                     "call site chose it, a test cannot set it without reaching around the " \
                     "object, and the same input becomes a different instant on a " \
                     "differently configured machine. A string is parsed once, at the seam, " \
                     "against a zone the request stated — and the moment travels from there " \
                     "as a value.",
            instead: MOMENT,
          )
        end

        def ambient(node)
          receiver = node.receiver
          return unless receiver&.const_type?
          return unless AMBIENT_CONSTANTS.include?(receiver.source.sub(/\A::/, ""))

          message_for(node.source, "request-scoped or process-wide state")
        end

        def zone(node)
          return unless ZONE_READS.include?(node.method_name)
          return unless node.receiver&.source == "Time"
          return if reported_as_a_clock?(node)

          explain(
            "`#{node.source}` reads the ambient zone.",
            because: "A zone nobody stated is a fact nobody declared. Where the " \
                     "requester's own zone is wanted, the action asks for it — and a " \
                     "request arriving without one bounces because that action asked, not " \
                     "because a default was quietly applied.",
            instead: MOMENT,
          )
        end

        # `Time.zone.now` is one piece of code and the clock message already covers it, so the
        # inner read is not reported twice. **Only the clock reads earn that**: exempting every
        # `Time.zone.*` chain left `Time.zone.parse(raw)` reported by nothing at all, while the
        # zone it applies is still one nobody stated.
        def reported_as_a_clock?(node)
          parent = node.parent
          return false unless parent&.send_type? && parent.receiver.equal?(node)

          CLOCKS.fetch("Time.zone", []).include?(parent.method_name)
        end

        def message_for(source, what)
          explain(
            "`#{source}` reads #{what} from outside the call.",
            because: "It is a dependency that does not appear in the signature, so the " \
                     "call site cannot see it and no reader can tell what this operation " \
                     "actually needs. Two callers get different behaviour from identical " \
                     "arguments, which is the bug nobody can reproduce.",
            instead: HANDED_IN,
          )
        end

        MOMENT = <<~RUBY
          # the caller reads the clock once, at the edge, and hands the moment down
          class ExpireHolds < Command
            def initialize(now:)
              @now = typed(now, ActiveSupport::TimeWithZone)
            end
          end

          # in the action, where the zone is asked for rather than assumed
          ExpireHolds.call(now: time_param!(:now, time_zone: time_zone_param!(:zone)))
        RUBY

        HANDED_IN = <<~RUBY
          # it arrives as an argument, so the signature says what this operation needs
          class SendReceipt < Command
            def initialize(api_key:)
              @api_key = typed(api_key, String)
            end
          end
        RUBY

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query shape])
        end
      end
    end
  end
end
