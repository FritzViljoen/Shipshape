# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/kinds"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `one-operation-one-class` (docs/laws/one-operation-one-class.md).
      #
      # An operation is a class with one public method, `call`, taking keyword arguments.
      # A second public method is a second operation, and it gets a second class.
      #
      # `call` itself stays public, and the guard that keeps a caller out of it is
      # `Shipshape/OnlyTheDoorIsCalled`, which refuses `SettleInvoice.new` at the call site —
      # so nobody can hold an operation to call anything on. Hiding `call` too was tried and
      # dropped: it bought a runtime backstop against a hole already refused, and cost the
      # shape every Rails developer already writes.
      #
      # The uniform shape is what lets one wrapper serve every call site — logging,
      # instrumentation, an audit trail, a migration seam. Four call conventions and none
      # of those can exist. It is also what leaves a new case nowhere to go but a new
      # class: a single-method class has no branch to grow.
      #
      # A collected parameter is refused as its own offence rather than tolerated, because
      # it is a hole in every other rule that inspects a signature — a keyword-less
      # initializer silently accepts a caller's keywords as one positional Hash and the
      # call succeeds.
      #
      # WHAT IT DOES NOT CATCH, and the law says so too: it cannot tell whether the one
      # method does one thing. A two-hundred-line `call` passes. Length is a separate
      # concern and this cop does not cover it.
      #
      # @example
      #   # bad — two public methods
      #   class SettleMonth < Workflow
      #     def call; end
      #     def preview; end
      #   end
      #
      #   # bad — a collected parameter
      #   class CreatePerson < Command
      #     def initialize(**options); end
      #   end
      #
      #   # good
      #   class CreatePerson < Command
      #     def initialize(name:); end
      #     def call; end
      #   end
      class OneOperationOneClass < Base
        include VisibilityHelp
        extend AutoCorrector
        include Explains

        SHAPE = <<~RUBY
          class SettleInvoice < Command
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

        # `initialize` is private in Ruby whatever the file says, and the law requires a
        # hand-written one — so it is never the public method this cop is counting.
        # `respond_to_missing?` is the same case: an override the language asks for.
        NOT_PUBLIC = %i[initialize initialize_copy respond_to_missing?].freeze

        def on_class(node)
          return unless operation?
          # **A nested class is a part, not the operation.** `ReplyDraft::Draft` is a shape,
          # and a shape's whole job is to expose the fields it was handed — judging it by
          # the operation's rules flags `attr_reader` on the one class that must have it.
          # Found by using this on a real refactor rather than by reading it.
          return if node.each_ancestor(:class).any?

          body = node.body
          statements = body.nil? ? [] : (body.begin_type? ? body.children : [body])

          check_entry_point(node, statements)
          return if body.nil?

          check_methods(node, statements)
          statements.each { |statement| check_reader(statement) }
        end

        # Only the operation's own entry points. A private helper taking positional
        # arguments is internal and nobody's business — the law is about what a CALLER may
        # hand an operation, and a caller can hand it only `initialize` and `call`.
        #
        # This checked every `def` at first, and on a well-built application it reported
        # sixteen offences that were all private helpers. A guard that fires on correct
        # code is not strict, it is wrong, and it is how a cop gets disabled wholesale.
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
            instead: <<~RUBY,
              # nearly always: it is a helper, and it goes under `private`
              class SettleInvoice < Command
                def call
                  success(total)
                end

                private

                def total
                  @lines.sum(&:amount)
                end
              end

              # occasionally: it is a second operation, and it gets its own class
              class TotalInvoice < Query
                def call
                  success(@lines.sum(&:amount))
                end
              end
            RUBY
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

        # **The entry point is defined here, never inherited.** The base class's `call` runs
        # whichever of the two this class implements, so a class implementing neither has no
        # work to run — and one that inherits its entry point from another operation is the
        # shape `an-operation-is-a-leaf` refuses, where the parent's `anonymous_call` made
        # the child public with nothing at the child saying so.
        # Whatever its visibility — this asks only whether it is there at all.
        def check_entry_point(node, statements)
          entries = definitions_in(statements).select do |definition|
            entry_names.include?(definition.method_name.to_s)
          end

          return add_offense(node.identifier, message: no_entry_point(node.identifier.source)) if entries.empty?
          return if entries.length == 1

          # **Both, and both private, is a fail-open.** `anonymous?` answers true, so the base
          # class dispatches to `anonymous_call` and the operation runs unauthenticated —
          # while the file appears to define an authorised `call`. Visibility cannot catch
          # this, because the correct shape is private too.
          entries.drop(1).each { |entry| add_offense(entry, message: two_entry_points(entry)) }
        end

        # `private def call; end` is a `send` wrapping a `def`, so a check that looks only at
        # direct children misses it — and then reports the class as defining no entry point
        # at all, which is the opposite of true.
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

        # **Instance methods and class methods have different rules, and mixing them was a
        # bug:** one list meant a class method counted towards the instance budget, so a
        # command with `def self.for` had its perfectly correct `def call` reported as a
        # third public method.
        def check_methods(node, statements)
          public_defs = statements.select { |statement| public_method?(statement) }

          check_instance_methods(node, public_defs.select(&:def_type?))
          check_class_methods(public_defs.select(&:defs_type?))
        end

        # **The entry point, and nothing else.** `initialize` and `call` are what a caller
        # hands arguments to; every other method is the operation's own business.
        def check_instance_methods(_node, definitions)
          helpers = definitions.reject { |definition| entry_names.include?(definition.method_name.to_s) }

          helpers.each_with_index do |definition, index|
            add_offense(definition, message: second_operation(definition)) do |corrector|
              # **One `private` above the first helper fixes every one of them at once.**
              # Attached to the first offence only — a second insert would stack two
              # `private` lines. Indexed over the helpers, not over every definition: the
              # entry point is usually first, and counting it meant the scaffold was pinned
              # to an offence that never came.
              scaffold_private(corrector, definition) if index.zero?
            end
          end
        end

        # **Above the first helper, below the entry point.** `initialize` and `call` stay
        # public: what stops a caller reaching them is `Shipshape/OnlyTheDoorIsCalled`, which
        # refuses `SettleInvoice.new` at the call site, so nobody can obtain an operation to
        # call anything on. Hiding `call` as well bought a runtime backstop against a hole
        # that already required constructing one — and cost the shape every Rails developer
        # already writes.
        def scaffold_private(corrector, definition)
          corrector.insert_before(definition, "private\n\n#{' ' * definition.loc.column}")
        end

        # **None.** The only class method an operation has is the base class's `call`, and
        # redefining that is `Shipshape/OperationsAreLeaves`' business — reporting it here
        # too would be one defect wearing two offences.
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
            instead: <<~RUBY,
              # a constructor helper is the caller's business, or its own operation
              SettleInvoice.call(invoice_id: invoice.id, settled_on: today)

              # a constant belongs on the class; a computation belongs in `call`
              class SettleInvoice < Command
                TERMS = 30

                def call
                  success(...)
                end
              end
            RUBY
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

        # Every input is a named keyword. Anything else is refused with the reason spelled
        # out, because "use keywords" without the why gets worked around rather than fixed.
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
          operation_kinds.include?(kind_of_inspected_file)
        end

        def kind_of_inspected_file
          @kind_of_inspected_file ||= kinds.for_path(processed_source.file_path)
        end

        def kinds
          @kinds ||= ::Shipshape::Kinds.new(settings: settings, base_dir: base_dir)
        end

        # Declared once, on the call-graph cop. Repeating the layout per cop would be a
        # second copy of one fact, and the copy is the one that goes stale.
        def settings
          @settings ||= ::Shipshape::Settings.layout(config)
        end

        def operation_kinds
          @operation_kinds ||= cop_config.fetch("OperationKinds", [])
        end

        def expected_name
          @expected_name ||= cop_config.fetch("PublicMethod", "call")
        end

        # **A closed pair, not an open list.** `anonymous_call` is the second because the
        # permission model requires it — an operation that runs before anyone is identified
        # says so by which method it implements. Without this the canon forbade the shape it
        # also demanded. A class defining BOTH is already refused as a second public method,
        # which is the answer that matters: two entry points would be two operations with
        # different authorisation wearing one class.
        def entry_names
          @entry_names ||= [expected_name, cop_config.fetch("AnonymousMethod", "anonymous_call")]
        end

        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
