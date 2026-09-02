# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `arguments-are-typed-at-construction`, and the declared-type half of
      # `a-time-names-its-zone`.
      class TypedArguments < Base
        include ReadsKinds

        GUARDS = %i[typed typed_array typed_hash].freeze

        # The declared type is caught here, at lint time, from the constant written at the
        # call site. `typed` catches the value itself at runtime — but only on the line
        # that actually runs, so this half still matters.
        NAIVE_MOMENTS = %w[Time DateTime].freeze

        UNNAMED = {
          restarg: "a positional splat",
          kwrestarg: "a keyword splat",
          forward_arg: "an argument forward",
          blockarg: nil,
        }.freeze

        SHAPE = <<~RUBY
          class SettleInvoice < Command
            def initialize(invoice_id:, settled_on:, note: nil)
              @invoice_id = typed(invoice_id, Integer)
              @settled_on = typed(settled_on, Date)
              @note = typed(note, String, allow_nil: true)   # absence says so, explicitly
            end
          end
        RUBY

        MOMENT = <<~RUBY
          class ExpireHolds < Command
            def initialize(now:, departs_on:)
              @now = typed(now, ActiveSupport::TimeWithZone)  # a point in time, placed
              @departs_on = typed(departs_on, Date)           # a calendar date, no zone by design
            end
          end
        RUBY

        def on_def(node)
          return unless node.method?(:initialize)
          return unless one_of?(governed_kinds)

          node.arguments.each { |argument| check_argument(argument, node) }
          guards(node).each { |guard| check_declared_type(guard) }
        end

        private

        def check_argument(argument, definition)
          case argument.type
          when :kwarg, :kwoptarg
            name = argument.name
            add_offense(argument, message: unguarded(name)) unless guarded?(definition, name)
          when :arg, :optarg
            add_offense(argument, message: not_a_keyword(argument.source, "a positional parameter"))
          else
            what = UNNAMED[argument.type]
            add_offense(argument, message: not_a_keyword(argument.source, what)) if what
          end
        end

        # `@on = typed(on, Date)` — the guard is reached somewhere in the body with this
        # keyword as an argument. Which line it sits on is not the cop's business.
        def guarded?(definition, name)
          guards(definition).any? do |send|
            send.arguments.any? { |argument| argument.lvar_type? && argument.children.first == name }
          end
        end

        def guards(definition)
          return [] unless definition.body

          definition.body.each_node(:send).select { |send| GUARDS.include?(send.method_name) }
        end

        # Walked per guard call rather than per keyword: one `typed` names one type, and a
        # keyword-by-keyword walk reports the same constant twice where two keywords share a
        # `typed_hash`.
        def check_declared_type(guard)
          guard.arguments.each do |argument|
            next unless argument.const_type?
            next unless NAIVE_MOMENTS.include?(argument.source.sub(/\A::/, ""))

            add_offense(argument, message: naive_moment(argument.source))
          end
        end

        def unguarded(name)
          explain(
            "`#{name}:` is stored without being asserted.",
            because: "The boundary is the point: past it nothing re-checks, so whatever " \
                     "arrives here is what the whole operation believes. An unasserted " \
                     "keyword means the failure surfaces somewhere further in, wearing " \
                     "the operation's name instead of the caller's, and usually as a " \
                     "`NoMethodError` on nil three files away.",
            instead: SHAPE,
          )
        end

        def naive_moment(source)
          explain(
            "`#{source}` names no zone, so this keyword accepts a moment nobody placed.",
            because: "A bare `#{source}` carries whatever offset the process happened to " \
                     "have, chosen by nobody, so the same instant renders as a different " \
                     "wall clock on a differently configured machine. This cop catches the " \
                     "declared type here, inside `initialize`, at lint time. `typed` catches " \
                     "the value itself at runtime, wherever it is called, so a naive " \
                     "#{source} still raises even from a call this cop cannot see.",
            instead: MOMENT,
          )
        end

        def not_a_keyword(source, what)
          explain(
            "`#{source}` is #{what}, not a named keyword.",
            because: "A keyword-less initializer silently accepts the caller's keywords as " \
                     "one Hash and the call succeeds — so the mistake is not caught here " \
                     "and not caught anywhere. It is also a hole in every rule that " \
                     "inspects the signature: nothing can assert what it holds.",
            instead: SHAPE,
          )
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query legacy_command legacy_query])
        end
      end
    end
  end
end
