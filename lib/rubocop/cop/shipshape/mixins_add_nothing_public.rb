# frozen_string_literal: true

require "shipshape/mixins"
require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the mixin half of `one-operation-one-class`
      # (docs/laws/one-operation-one-class.md).
      #
      # An operation has one public method. A module included into one can put back
      # everything `Shipshape/OneOperationOneClass` just took away, and it does it in a file
      # that cop never looks at — it walks classes, and a concern is a module.
      #
      # **A module cannot be judged by its own file.** `Paying` is correct in a shape, whose
      # whole job is to be read, and wrong in a command, which answers one message. So this
      # scans the operation trees for what they include, and a module named there is held to
      # the operation's rules wherever it lives.
      #
      # WHAT IT DOES NOT CATCH: the include is read with a regular expression, so a module
      # mixed in dynamically — `include Object.const_get(name)` — is invisible, and so is one
      # reached through an alias. It matches a written `include Paying` against a module
      # declared `Paying` or `Billing::Paying`, which **over-fires** where two modules share a
      # last segment and only one is a mixin. Over-firing says "make these private", which is
      # a defensible thing to be told; under-firing would be silence. **Tests are exempt.**
      #
      # **The exact version of this runs in the application's own suite**, as
      # `test/shipshape/operations_expose_nothing_test.rb`, which subtracts the base class's
      # public surface from the loaded operation's and so sees every route a mixin can take.
      # This cop exists because that one needs a booted application; it is the fast
      # approximation, and it names the file to fix.
      #
      # @example
      #   # bad — included into a command, so `total` is public on every command that has it
      #   module Paying
      #     def total
      #       @lines.sum(&:amount)
      #     end
      #   end
      #
      #   # good
      #   module Paying
      #     private
      #
      #     def total
      #       @lines.sum(&:amount)
      #     end
      #   end
      class MixinsAddNothingPublic < Base
        include VisibilityHelp
        extend AutoCorrector
        include ReadsKinds

        # `initialize` is private whatever the file says, and `respond_to_missing?` and
        # `included` are hooks the language and Ruby's own module protocol ask for.
        NOT_PUBLIC = %i[initialize initialize_copy respond_to_missing? included prepended].freeze

        READERS = %i[attr_reader attr_accessor attr_writer].freeze

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

        # A class method on a mixin is `def self.x`, which does not travel through `include`
        # at all — it lands on the module object. Nothing an operation gets, so nothing here.
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
            instead: <<~RUBY,
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
            instead: <<~RUBY,
              module Paying
                private

                attr_reader :lines
              end
            RUBY
          )
        end

        def mixin?(node)
          mixins.mixed_into_an_operation?(declared_name(node))
        end

        # **The name as the file declares it, namespace and all.** An earlier version read
        # `node.identifier` alone and skipped anything nested, so `module Billing; module
        # Paying` was never checked — the outer module is not the mixin and the inner one was
        # thrown away before it was asked about. Nesting is also what stops one module being
        # reported twice: an inner `Paying::Inner` matches no written `include Paying`.
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
