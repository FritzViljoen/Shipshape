# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `arguments-are-typed-at-construction`.
      #
      # Every keyword an operation takes passes through a type guard, in a hand-written
      # initializer, once. Past that line nothing re-checks: a failure at the guard is the
      # caller's defect, and after it the operation's own.
      #
      # **Anything that is not a named keyword is its own offence** — `**rest`, `(...)`, a
      # positional parameter — because a keyword-less initializer silently accepts the
      # caller's keywords as one Hash and the call succeeds, which is worse than failing.
      #
      # WHAT IT DOES NOT CATCH: it checks that a keyword **is** guarded, never that the type
      # named is the right one — `typed(person, Date)` passes. It cannot see a guard called
      # through a helper it does not know by name.
      #
      # @example
      #   # bad — the keyword is stored unasserted
      #   def initialize(on:)
      #     @on = on
      #   end
      #
      #   # bad — a keyword-less initializer swallows the caller's keywords as one Hash
      #   def initialize(**options)
      #
      #   # good
      #   def initialize(on:, party:)
      #     @on = typed(on, Date)
      #     @party = typed(party, Party)
      #   end
      class TypedArguments < Base
        include ReadsKinds

        GUARDS = %i[typed typed_array typed_hash].freeze

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
          return false unless definition.body

          definition.body.each_node(:send).any? do |send|
            GUARDS.include?(send.method_name) &&
              send.arguments.any? { |argument| argument.lvar_type? && argument.children.first == name }
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
