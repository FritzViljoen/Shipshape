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

        # A moment is `ActiveSupport::TimeWithZone`; a calendar date is `Date`. A bare `Time`
        # or `DateTime` is neither, and **this is the only place the rule can be held.** At
        # runtime the guard cannot tell them apart — `TimeWithZone` answers `is_a?(Time)` with
        # true, so a naive value declared `Time` walks through. The declared type is written in
        # the source, so a reader of the source can refuse it and nothing else can.
        NAIVE_MOMENTS = %w[Time DateTime].freeze

        COLLECTIONS = %w[Array Hash].freeze

        UNNAMED = {
          restarg: "a positional splat",
          kwrestarg: "a keyword splat",
          forward_arg: "an argument forward",
          blockarg: nil,
        }.freeze

        def on_def(node)
          return unless node.method?(:initialize)
          return unless one_of?(governed_kinds)

          node.arguments.each { |argument| check_argument(argument, node) }
          guards(node).each { |guard| check_declared_type(guard) }
        end

        # `typed(lines, Array).each { |line| typed(line, Line) }` — the collection guard written
        # out by hand, which is the one shape that passes `on_def` and still says it wrong.
        def on_block(node)
          return unless one_of?(governed_kinds)

          signature = signature_for(node)
          return unless signature

          add_offense(node, message: hand_rolled(signature))
        end

        private

        def signature_for(node)
          guarded = bare_collection_guard(node)
          return unless guarded

          subject, collection = guarded
          collection == "Array" ? array_signature(node, subject) : hash_signature(node, subject)
        end

        def bare_collection_guard(node)
          each = node.send_node
          return unless each.method_name == :each

          call = each.receiver
          return unless call.respond_to?(:send_type?) && call.send_type? && call.receiver.nil?
          return unless call.method_name == :typed && call.arguments.length == 2

          collection = named_constant(call.arguments.last)
          [call.arguments.first.source, collection] if COLLECTIONS.include?(collection)
        end

        def array_signature(node, subject)
          return unless node.arguments.length == 1

          element = asserted_type(node.body, node.arguments.first.name)

          "typed_array(#{subject}, #{element})" if element
        end

        def hash_signature(node, subject)
          return unless node.arguments.length == 2
          return unless node.body&.begin_type? && node.body.children.length == 2

          key, value = node.body.children.zip(node.arguments).map do |check, argument|
            asserted_type(check, argument.name)
          end

          "typed_hash(#{subject}, #{key}, #{value})" if key && value
        end

        # The type this check asserts the block's own parameter to be, when it is exactly
        # `typed(name, Type)`. Anything else is a check no signature can express.
        def asserted_type(check, name)
          return unless check.respond_to?(:send_type?) && check.send_type? && check.receiver.nil?
          return unless check.method_name == :typed && check.arguments.length == 2

          subject, type = check.arguments
          return unless subject.lvar_type? && subject.children.first == name

          named_constant(type)
        end

        def named_constant(node)
          node.const_type? ? node.source.sub(/\A::/, "") : nil
        end

        def hand_rolled(signature)
          explain(
            "The block asserts by hand what `#{signature}` states as a signature.",
            because: "The two do the same work and only one of them says so. The hand-rolled " \
                     "loop reports `expected Line, got NilClass` with no index and no argument " \
                     "name, where the signature names both; it leans on `Array#each` answering " \
                     "its receiver, which the reader has to already know for the assignment to " \
                     "parse; and for a Hash it spends four lines saying what a key and a value " \
                     "type say in one. A Hash caught here is often a shape nobody has named — " \
                     "if the entries are not one homogeneous map, the fix is to define it.",
            instead: SIGNED,
          )
        end

        SIGNED = <<~RUBY
          @lines = typed_array(lines, Line)
          @rates = typed_hash(rates, Symbol, BigDecimal)

          # the block form stays, for the element check no signature can express
          @variants = typed(variants, Array).each { |v| typed_enum(v, ALLOWED) }
        RUBY

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
                     "wall clock on a differently configured machine. The runtime guard " \
                     "cannot catch this one: `ActiveSupport::TimeWithZone` answers " \
                     "`is_a?(Time)` with true, so a naive value declared `#{source}` passes " \
                     "the assertion. The declared type is the only place the difference is " \
                     "visible, and this is that place.",
            instead: MOMENT,
          )
        end

        MOMENT = <<~RUBY
          class ExpireHolds < Command
            def initialize(now:, departs_on:)
              @now = typed(now, ActiveSupport::TimeWithZone)  # a point in time, placed
              @departs_on = typed(departs_on, Date)           # a calendar date, no zone by design
            end
          end
        RUBY

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

        SHAPE = <<~RUBY
          class SettleInvoice < Command
            def initialize(invoice_id:, settled_on:, note: nil)
              @invoice_id = typed(invoice_id, Integer)
              @settled_on = typed(settled_on, Date)
              @note = typed(note, String, allow_nil: true)   # absence says so, explicitly
            end
          end
        RUBY

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query legacy_command legacy_query])
        end
      end
    end
  end
end
