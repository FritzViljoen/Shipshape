# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the entering half of `nothing-travels-off-the-call-path`, and the ambient-zone,
      # naive-parse and naive-cast halves of `a-time-names-its-zone`.
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

        # `Date.parse` and `DateTime.new` are absent — each already names its own zone.
        NAIVE_PARSERS = {
          "Time" => %i[parse strptime iso8601],
          "DateTime" => %i[parse strptime iso8601],
        }.freeze

        # These keep the instant they are given; `cast` reports them for a different fact.
        NAIVE_CASTS = %i[to_time to_datetime].freeze

        AMBIENT_CONSTANTS = %w[ENV Thread Current RequestStore].freeze

        ZONE_READS = %i[zone zone_default].freeze

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

        def on_send(node)
          return unless one_of?(governed_kinds)

          reason = clock(node) || naive_new(node) || naive_parse(node) || naive_cast(node) ||
                   ambient(node) || zone(node)
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

          clock_message(node.source)
        end

        def clock_message(source)
          explain(
            "`#{source}` reads the clock, and nothing at the call site chose it.",
            because: "The current time is a dependency that is not on the call path: the " \
                     "caller cannot see it, a test cannot set it without reaching around " \
                     "the object, and the value differs on every run. The caller knows " \
                     "when it is running. The operation does not, and must not guess. " \
                     "A bare `Time.now` also carries whatever offset the process had, " \
                     "chosen by nobody.",
            instead: MOMENT,
          )
        end

        # Zero args is `Time.now` restated; with date parts and no offset it is a naive parse.
        def naive_new(node)
          return unless node.receiver&.source == "Time" && node.method_name == :new

          return clock_message(node.source) if node.arguments.empty?
          return if offset_given?(node)

          naive_parse_message(node.source)
        end

        def offset_given?(node)
          node.arguments.length > 6 || zone_named?(node)
        end

        def zone_named?(node)
          node.arguments.any? do |argument|
            argument.hash_type? && argument.pairs.any? { |pair| pair.key.sym_type? && pair.key.value == :in }
          end
        end

        # `request_handling`/`entry_point` are ungoverned; a request parse is NoInlineParamParse's.
        def naive_parse(node)
          receiver = node.receiver&.source
          return unless NAIVE_PARSERS.fetch(receiver, []).include?(node.method_name)

          naive_parse_message(node.source)
        end

        def naive_parse_message(source)
          explain(
            "`#{source}` parses a moment against no stated zone.",
            because: "The string names no offset, so the process supplies one — and the " \
                     "same string lands on a different instant on a differently " \
                     "configured machine. A moment is parsed once, at the seam, against " \
                     "a zone the request stated, and travels from there as a value.",
            instead: MOMENT,
          )
        end

        # `Time.zone.at` does not match: its receiver is `Time.zone`, not the `Time` constant.
        def naive_cast(node)
          return unless bare_cast?(node) || epoch_at?(node)

          explain(
            "`#{node.source}` casts to a bare moment with no zone attached.",
            because: "The instant it names is unchanged — the same epoch, read back in " \
                     "any process zone, is the same moment. What changes is the offset " \
                     "now stamped on the value: whatever the process had, not whichever " \
                     "zone the original carried. A caller reading the hour or the day " \
                     "off the result reads the wrong wall clock for anyone elsewhere. " \
                     "And the cast is not this operation's to make: a moment is parsed " \
                     "and given its zone once, at the seam, and travels from there as a " \
                     "value — a cast in here is that same step, arriving late and with " \
                     "the wrong zone in hand.",
            instead: MOMENT,
          )
        end

        def bare_cast?(node)
          node.receiver && NAIVE_CASTS.include?(node.method_name) && node.arguments.empty?
        end

        def epoch_at?(node)
          node.receiver&.source == "Time" && node.method_name == :at && !zone_named?(node)
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
          # `Time.zone.now` is one piece of code, and the clock message already covers it.
          return if node.parent&.send_type? && node.parent.receiver.equal?(node)

          explain(
            "`#{node.source}` reads the ambient zone.",
            because: "A zone nobody stated is a fact nobody declared. Where the " \
                     "requester's own zone is wanted, the action asks for it — and a " \
                     "request arriving without one bounces because that action asked, not " \
                     "because a default was quietly applied.",
            instead: MOMENT,
          )
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

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query shape])
        end
      end
    end
  end
end
