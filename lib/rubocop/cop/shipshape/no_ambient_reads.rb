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

        AMBIENT_CONSTANTS = %w[ENV Thread Current RequestStore].freeze

        ZONE_READS = %i[zone zone_default].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)

          reason = clock(node) || ambient(node) || zone(node)
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
