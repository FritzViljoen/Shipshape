# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `code-is-written-not-generated`.
      class NoGeneratedInterfaces < Base
        include ReadsKinds

        DEFINERS = %i[define_method define_singleton_method].freeze
        EVALUATORS = %i[class_eval module_eval instance_eval eval instance_variable_set const_set].freeze
        DISPATCH = %i[method_missing respond_to_missing?].freeze

        # **`send` makes every other guard optional.** Private is a convention it steps over,
        # the call graph is a matrix it routes around, and the method it names cannot be
        # found by grepping for the call. Nothing in an operation needs it: the class knows
        # its own methods by name.
        SENDERS = %i[send __send__ public_send].freeze

        WRITTEN = <<~RUBY
          # written out: greppable, renameable, and the reader is done in one line
          class Invoice < Shape
            def initialize(number:, issued_on:)
              @number = typed(number, String)
              @issued_on = typed(issued_on, Date)
            end

            attr_reader :number, :issued_on
          end
        RUBY

        def on_send(node)
          return unless one_of?(governed_kinds)

          if SENDERS.include?(node.method_name)
            add_offense(node, message: dispatching_dynamically(node.method_name))
          elsif DEFINERS.include?(node.method_name)
            add_offense(node, message: defining(node.method_name))
          elsif EVALUATORS.include?(node.method_name)
            add_offense(node, message: evaluating(node.method_name))
          end
        end

        def on_def(node)
          return unless DISPATCH.include?(node.method_name)
          return unless one_of?(governed_kinds)

          add_offense(node, message: dispatching(node.method_name))
        end

        private

        def defining(name)
          explain(
            "`#{name}` writes methods a reader would otherwise grep for.",
            because: "The method exists at runtime and not in the source, so the one move " \
                     "every reader makes — search for the name, read what it does — finds " \
                     "nothing. Generation compressed the writing and expanded the reading, " \
                     "and the reading is paid on every visit, forever, by people who are " \
                     "not the writer.",
            instead: WRITTEN,
          )
        end

        def dispatching_dynamically(name)
          explain(
            "`#{name}` chooses a method at runtime.",
            because: "It steps over `private`, routes around the call graph, and names a " \
                     "method that cannot be found by grepping for the call — so every " \
                     "other guard here becomes optional wherever it appears. A class knows " \
                     "its own methods by name; if this one does not, the thing being " \
                     "chosen is data and belongs in a row.",
            instead: WRITTEN,
          )
        end

        def evaluating(name)
          explain(
            "`#{name}` builds code out of a string.",
            because: "Nothing can read it: not a grep, not a rename, not the editor's " \
                     "jump-to-definition, not a static check. Its errors surface at the " \
                     "point of use with a trace that does not name this file.",
            instead: WRITTEN,
          )
        end

        def dispatching(name)
          explain(
            "`#{name}` answers for methods that were never written.",
            because: "The class's interface is now whatever the dispatch happens to " \
                     "accept, so no reader can enumerate it and every typo becomes a " \
                     "silent success. A caller cannot tell a supported call from one that " \
                     "will fall through until it runs.",
            instead: WRITTEN,
          )
        end

        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow command query io_command io_query legacy_command legacy_query shape record],
          )
        end
      end
    end
  end
end
