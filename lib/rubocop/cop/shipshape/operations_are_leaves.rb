# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `an-operation-is-a-leaf`.
      #
      # **A base class is inherited exactly once.** `SettleInvoice < Command` is an
      # operation; `AdminSettleInvoice < SettleInvoice` is not, and the depth is what makes
      # the model unsafe rather than merely untidy.
      #
      # Everything the door decides — the permission check, the transaction, the return-type
      # assertion — it decides for the class in front of it. A second level inherits those
      # answers without appearing to ask the question, so a subclass of an operation that
      # implements `anonymous_call` runs unauthenticated with nothing at its own definition
      # saying so. Review found exactly that: `class AdminUpload < PublicUpload` was public,
      # and `grep -rn "def anonymous_call"` — the audit the permission law calls
      # authoritative — did not name it.
      #
      # **And the door itself is not overridable.** `def self.call` in an operation replaces
      # the base class's entry point, taking the check and the transaction with it.
      #
      # WHAT IT DOES NOT CATCH: it reads the **superclass constant**, so a class built by
      # `Class.new(SettleInvoice)` or assigned through a constant it cannot resolve to a file
      # is invisible. It cannot see a module that redefines `call` after inclusion. Depth is
      # measured through governed files only: an operation inheriting from something in a
      # tree the layout does not declare is left alone rather than guessed at.
      #
      # @example
      #   # bad — a second level inherits the door's answers without asking
      #   class AdminUpload < PublicUpload
      #   end
      #
      #   # bad — the door belongs to the base class
      #   class Sneaky < Command
      #     def self.call(**arguments)
      #       new(**arguments).call
      #     end
      #   end
      #
      #   # good — one level, and the shared part is a collaborator, not an ancestor
      #   class AdminUpload < Command
      #     def call
      #       Upload.call(file: @file)
      #     end
      #   end
      class OperationsAreLeaves < Base
        include ReadsKinds

        DOOR = :call

        def on_class(node)
          return unless one_of?(governed_kinds)

          check_depth(node)
          check_door(node)
        end

        private

        def check_depth(node)
          parent = node.parent_class
          return unless parent&.const_type?

          kind = kinds.for_constant(parent.source.sub(/\A::/, ""))
          return unless governed_kinds.include?(kind)

          add_offense(parent, message: too_deep(node.identifier.source, parent.source, kind))
        end

        # `def self.call` — the class method, not the instance one the operation must define.
        def check_door(node)
          return unless node.body

          node.body.each_node(:defs).each do |definition|
            next unless definition.method?(DOOR)
            next unless definition.children.first.self_type?

            add_offense(definition, message: door_replaced(node.identifier.source))
          end
        end

        def too_deep(name, parent, kind)
          explain(
            "`#{name}` inherits from `#{parent}`, which is already #{article(kind)} #{kind}.",
            because: "A base class is inherited exactly once. Everything the door decides — " \
                     "the permission check, the transaction, the return-type assertion — it " \
                     "decides for the class in front of it, and a second level inherits " \
                     "those answers without appearing to ask the question. A subclass of an " \
                     "operation that implements `anonymous_call` runs unauthenticated with " \
                     "nothing at its own definition saying so, and the audit for public " \
                     "operations does not name it.",
            instead: <<~RUBY,
              # one level from the base class, always
              class AdminUpload < Command
                def call
                  # what was shared is a collaborator, not an ancestor
                  Upload.call(file: @file)
                end
              end
            RUBY
          )
        end

        def door_replaced(name)
          explain(
            "`#{name}` defines `self.#{DOOR}`, which is the base class's door.",
            because: "The door is where the permission check runs, where the transaction " \
                     "opens, and where the return type is asserted. Replacing it takes all " \
                     "three with it, and the replacement looks like ordinary code — every " \
                     "caller still writes `#{name}.call(...)` and nothing indicates the " \
                     "guarantees are gone.",
            instead: <<~RUBY,
              # define the instance method; the base class calls it
              class SettleInvoice < Command
                def call
                  success(...)
                end
              end
            RUBY
          )
        end

        def article(kind)
          kind.to_s.start_with?("a", "e", "i", "o", "u") ? "an" : "a"
        end

        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow command query io_command io_query legacy_command legacy_query],
          )
        end
      end
    end
  end
end
