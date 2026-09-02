# frozen_string_literal: true

require "shipshape/mixins"
require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the mixin half of `one-operation-one-class`.
      class MixinsAddNothingPublic < Base
        include VisibilityHelp
        extend AutoCorrector
        include ReadsKinds

        # `initialize` is private regardless; the rest are hooks the language asks for.
        NOT_PUBLIC = %i[initialize initialize_copy respond_to_missing? included prepended].freeze

        READERS = %i[attr_reader attr_accessor attr_writer].freeze

        PRIVATE_OR_QUERY = <<~RUBY
          # the methods stay, and go under `private` — an operation's helpers, shared
          module Paying
            private

            def total
              @lines.sum(&:amount)
            end
          end

          # if callers really need the answer, it is a query, not a mixin
          class TotalOf < Query
            def call
              success(@lines.sum(&:amount))
            end
          end
        RUBY

        READER = <<~RUBY
          module Paying
            private

            attr_reader :lines
          end
        RUBY

        def on_module(node)
          return unless mixin?(node)

          body = node.body
          return if body.nil?

          statements = body.begin_type? ? body.children : [body]
          check_methods(statements)
          statements.each { |statement| check_reader(statement) }
        end

        private

        def check_methods(statements)
          helpers = statements.select { |statement| public_method?(statement) }

          helpers.each_with_index do |definition, index|
            add_offense(definition, message: public_in_a_mixin(definition)) do |corrector|
              # One `private` above the first public method fixes all of them. Attached to
              # the first offence only — a second insert would stack two `private` lines.
              scaffold_private(corrector, definition) if index.zero?
            end
          end
        end

        def scaffold_private(corrector, definition)
          corrector.insert_before(definition, "private\n\n#{' ' * definition.loc.column}")
        end

        def check_reader(node)
          return unless node.respond_to?(:send_type?) && node.send_type?
          return unless node.receiver.nil? && READERS.include?(node.method_name)
          return unless node_visibility(node) == :public

          add_offense(node, message: exposed_state(node))
        end

        def public_method?(node)
          return false unless node.respond_to?(:def_type?) && node.def_type?
          return false if NOT_PUBLIC.include?(node.method_name)

          node_visibility(node) == :public
        end

        # `def self.x` lands on the module object and does not travel through `include`.
        def public_in_a_mixin(definition)
          explain(
            "`#{definition.method_name}` is public, and this module is mixed into an " \
            "operation, which has one public method.",
            because: "An operation exposes `call` and nothing else, and a module puts its " \
                     "methods on every class that includes it — so a public method here is " \
                     "a public method on each of those operations, added in a file none of " \
                     "them mention. That is the surface `one-operation-one-class` closes, " \
                     "reopened somewhere nobody looks for it. The same module is perfectly " \
                     "correct with these methods public if it is mixed into a shape, whose " \
                     "job is to be read; what makes it wrong is where it is going.",
            instead: PRIVATE_OR_QUERY,
          )
        end

        def exposed_state(node)
          explain(
            "An operation exposes no state, and this module is mixed into one. " \
            "`#{node.method_name}` here is a public method on every operation that " \
            "includes it.",
            because: "A reader invites a caller to ask instead of tell: it reaches in, gets " \
                     "a value, and decides something the operation should have decided. " \
                     "What the operation has to say, it answers from `call`.",
            instead: READER,
          )
        end

        def mixin?(node)
          mixins.mixed_into_an_operation?(declared_name(node))
        end

        # Namespace and all: reading `node.identifier` alone never checked `module Billing;
        # module Paying`. Nesting also stops one module being reported twice.
        def declared_name(node)
          outer = node.each_ancestor(:module, :class).map { |scope| scope.identifier.source }

          (outer.reverse + [node.identifier.source]).join("::").sub(/\A::/, "")
        end

        def mixins
          @mixins ||= ::Shipshape::Mixins.new(
            settings: settings, base_dir: base_dir, operation_kinds: operation_kinds,
          )
        end

        def operation_kinds
          @operation_kinds ||= cop_config.fetch("OperationKinds", [])
        end

      end
    end
  end
end
