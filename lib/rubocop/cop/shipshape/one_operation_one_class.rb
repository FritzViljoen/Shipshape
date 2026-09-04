# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      class OneOperationOneClass < Base
        include VisibilityHelp
        extend AutoCorrector
        include ReadsKinds

        SHAPE = <<~RUBY
          class SettleInvoice < Deed
            def initialize(invoice_id:, settled_on:)   # named keywords, asserted here
              @invoice_id = invoice_id
              @settled_on = settled_on
            end

            def call                                   # one public method, always `call`
              success(...)
            end

            private                                    # everything else, including readers

            attr_reader :invoice_id, :settled_on
          end
        RUBY

        READERS = %i[attr_reader attr_accessor attr_writer].freeze

        # `initialize` is private whatever the file says, and `respond_to_missing?` is an
        # override the language asks for. Neither is a public method this counts.
        NOT_PUBLIC = %i[initialize initialize_copy respond_to_missing?].freeze

        SPLIT = <<~RUBY
          # nearly always: it is a helper, and it goes under `private`
          class SettleInvoice < Deed
            def call
              success(total)
            end

            private

            def total
              @lines.sum(&:amount)
            end
          end

          # occasionally: it is a second operation, and it gets its own class
          class TotalInvoice < Question
            def call
              success(@lines.sum(&:amount))
            end
          end
        RUBY

        ENTRANCE = <<~RUBY
          # a constructor helper is the caller's business, or its own operation
          SettleInvoice.call(invoice_id: invoice.id, settled_on: today)

          # a constant belongs on the class; a computation belongs in `call`
          class SettleInvoice < Deed
            TERMS = 30

            def call
              success(...)
            end
          end
        RUBY

        def on_class(node)
          return unless operation?
          # A nested class is a part: judging `ReplyDraft::Draft` by the operation's rules
          # flags `attr_reader` on the one class that must have it. Found on a real refactor.
          return if node.each_ancestor(:class).any?

          body = node.body
          statements = body.nil? ? [] : (body.begin_type? ? body.children : [body])

          check_entry_point(node, statements)
          return if body.nil?

          check_methods(node, statements)
          statements.each { |statement| check_reader(statement) }
        end

        # Only the operation's own entry points: the law is about what a caller may hand one.
        # Checking every `def` reported sixteen offences on a good application, all helpers.
        def on_def(node)
          return unless operation?
          return unless entry_point?(node)

          node.arguments.each { |argument| check_parameter(argument) }
        end
        alias on_defs on_def

        private

        def second_operation(definition)
          explain(
            "`#{definition.method_name}` is public, and an operation's only public method " \
            "is `#{expected_name}`.",
            because: "Everything an operation does apart from answering is private — a " \
                     "public helper is reachable from anywhere the class is, so it is part " \
                     "of the contract whether or not anyone meant it to be, and it cannot " \
                     "be renamed or removed without finding every caller. Where it really " \
                     "is a second operation, two public methods are two operations sharing " \
                     "one constructor, and that constructor ends up carrying the union of " \
                     "what both need — so nothing about the class can be asserted at " \
                     "construction. Only a shape exposes anything, because a shape's whole " \
                     "job is to be read.",
            instead: SPLIT,
          )
        end

        def exposed_state(node)
          explain(
            "An operation exposes no state. `#{node.method_name}` here is a public " \
            "method in all but name.",
            because: "A reader invites a caller to ask instead of tell: it reaches in, " \
                     "gets a value and decides something the operation should have " \
                     "decided. What the operation has to say, it answers from `call`.",
            instead: SHAPE,
          )
        end

        def untyped_parameter(argument, why)
          explain(
            "An operation takes named keywords. `#{argument.source}` is #{why}.",
            because: "A positional or splatted argument is a hole in every rule that " \
                     "inspects the signature — nothing can assert what it holds, and the " \
                     "call site reads as a tuple whose meaning lives somewhere else.",
            instead: SHAPE,
          )
        end

        def entry_point?(node)
          node.method_name == :initialize || entry_names.include?(node.method_name.to_s)
        end

        # Defined here, never inherited: one inheriting its entry point is the shape
        # `an-operation-is-a-leaf` refuses, where a parent's `anonymous_call` made the child
        def check_entry_point(node, statements)
          entries = definitions_in(statements).select do |definition|
            entry_names.include?(definition.method_name.to_s)
          end

          return add_offense(node.identifier, message: no_entry_point(node.identifier.source)) if entries.empty?
          return if entries.length == 1

          # Both, and both private, is a fail-open: `anonymous?` answers true and the operation
          # runs unauthenticated while the file appears to define an authorised `call`.
          entries.drop(1).each { |entry| add_offense(entry, message: two_entry_points(entry)) }
        end

        # `private def call; end` is a `send` wrapping a `def`: looking only at direct children
        # reports the class as defining no entry point at all.
        def definitions_in(statements)
          statements.flat_map do |statement|
            next statement if statement.def_type?
            next statement.arguments.select(&:def_type?) if inline_visibility?(statement)

            []
          end
        end

        def inline_visibility?(statement)
          statement.respond_to?(:send_type?) && statement.send_type? &&
            %i[private public protected].include?(statement.method_name)
        end

        def two_entry_points(definition)
          explain(
            "`#{definition.method_name}` is a second entry point, and an operation has one.",
            because: "The base class dispatches to `#{entry_names.last}` whenever a class " \
                     "defines it, so a class defining both runs unauthenticated while " \
                     "appearing to define an authorised `#{expected_name}`. Which of the " \
                     "two a class implements is what decides whether it is checked, so it " \
                     "cannot implement both.",
            instead: SHAPE,
          )
        end

        def no_entry_point(name)
          explain(
            "`#{name}` defines neither `#{expected_name}` nor `#{entry_names.last}`.",
            because: "The base class's `#{expected_name}` runs whichever of the two this " \
                     "class implements, so a class implementing neither has nothing to " \
                     "run — and one that inherits an entry point from another operation " \
                     "inherits that operation's answers, including whether it needs an " \
                     "actor at all. Which of the two it is must be readable here, in this " \
                     "file, because that is what decides whether the operation is checked.",
            instead: SHAPE,
          )
        end

        # Separate lists: one meant `def self.for` pushed a correct `def call` over the budget
        # and reported it as a third public method.
        def check_methods(node, statements)
          public_defs = statements.select { |statement| public_method?(statement) }

          check_instance_methods(node, public_defs.select(&:def_type?))
          check_class_methods(public_defs.select(&:defs_type?))
        end

        def check_instance_methods(_node, definitions)
          helpers = definitions.reject { |definition| entry_names.include?(definition.method_name.to_s) }

          helpers.each_with_index do |definition, index|
            add_offense(definition, message: second_operation(definition)) do |corrector|
              # Attached to the first offence only, or a second insert stacks two `private`
              # lines. Indexed over the helpers: the entry point is usually first.
              scaffold_private(corrector, definition) if index.zero?
            end
          end
        end

        # Above the first helper, below the entry point. `call` stays public because
        # `Shipshape/OnlyTheDoorIsCalled` refuses `SettleInvoice.new` at the call site.
        def scaffold_private(corrector, definition)
          corrector.insert_before(definition, "private\n\n#{' ' * definition.loc.column}")
        end

        # None: redefining the base class's `call` is `Shipshape/OperationsAreLeaves`' business.
        def check_class_methods(definitions)
          definitions.reject { |definition| definition.method?(expected_name.to_sym) }
                     .each { |definition| add_offense(definition, message: class_method(definition)) }
        end

        def class_method(definition)
          explain(
            "`self.#{definition.method_name}` is a public class method, and an operation " \
            "has none.",
            because: "An operation's class surface is exactly what the base class gives it: " \
                     "`call`, and nothing else. A second entrance means the wrapper that " \
                     "serves every call site — the permission check, the transaction, the " \
                     "return-type assertion — is not on the path that call took, and " \
                     "nothing at the call site shows which entrance was used.",
            instead: ENTRANCE,
          )
        end

        def public_method?(node)
          return false unless node.respond_to?(:def_type?) && (node.def_type? || node.defs_type?)
          return false if NOT_PUBLIC.include?(node.method_name)

          node_visibility(node) == :public
        end

        def check_reader(node)
          return unless node.respond_to?(:send_type?) && node.send_type?
          return unless node.receiver.nil? && READERS.include?(node.method_name)
          return unless node_visibility(node) == :public

          add_offense(node, message: exposed_state(node))
        end

        def check_parameter(argument)
          why = reason_to_refuse(argument)
          return if why.nil?

          add_offense(argument, message: untyped_parameter(argument, why))
        end

        def reason_to_refuse(argument)
          case argument.type
          when :arg, :optarg then "positional"
          when :restarg then "a collected positional"
          when :kwrestarg then "a collected keyword"
          when :forward_arg then "a forwarded signature, which names nothing at all"
          end
        end

        def operation?
          one_of?(operation_kinds)
        end

        def operation_kinds
          @operation_kinds ||= cop_config.fetch("OperationKinds", [])
        end

        def expected_name
          @expected_name ||= cop_config.fetch("PublicMethod", "call")
        end

        # A closed pair: an operation running before anyone is identified says so by which of
        # the two it implements. Defining both is already refused as a second public method.
        def entry_names
          @entry_names ||= [expected_name, cop_config.fetch("AnonymousMethod", "anonymous_call")]
        end

      end
    end
  end
end
