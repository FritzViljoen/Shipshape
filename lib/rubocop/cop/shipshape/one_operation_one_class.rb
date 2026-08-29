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

          body = node.body
          return if body.nil?

          statements = body.begin_type? ? body.children : [body]
          check_methods(statements)
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
            "An operation has one public method. `#{definition.method_name}` is a second.",
            because: "Two public methods are two operations sharing one constructor, and " \
                     "the constructor ends up carrying the union of what both need. The " \
                     "class then has no arguments that are always required, so nothing " \
                     "about it can be asserted at construction.",
            instead: SHAPE,
          )
        end

        def wrong_name(definition)
          explain(
            "An operation's public method is `#{expected_name}`, " \
            "not `#{definition.method_name}`.",
            because: "One shape means one wrapper can serve every call site — logging, " \
                     "transactions, instrumentation, the test harness. A second verb " \
                     "means every one of those has to know about both.",
            instead: SHAPE,
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
          node.method_name == :initialize || node.method_name.to_s == expected_name
        end

        def check_methods(statements)
          public_defs = statements.select { |statement| public_method?(statement) }

          public_defs.each_with_index do |definition, index|
            next add_offense(definition, message: second_operation(definition)) if index.positive?
            next if definition.method_name.to_s == expected_name

            add_offense(definition, message: wrong_name(definition))
          end
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

        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
