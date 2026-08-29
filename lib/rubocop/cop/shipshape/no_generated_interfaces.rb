# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `code-is-written-not-generated`.
      #
      # **This law does not forbid metaprogramming. It forbids yours.** The framework's own
      # conventions are exempt, deliberately: they have a large public corpus, so any reader
      # — person or agent — arrives already knowing what they mean. A convention invented
      # here has a corpus of one repository, so it has to be re-derived from source on every
      # read, by every reader, and it is re-derived wrong sometimes.
      #
      # Generation compresses the writing and expands the reading. That was a good trade when
      # writing was the expensive half.
      #
      # WHAT IT DOES NOT CATCH: it names **constructs, not intent**. A gem doing this on your
      # behalf is invisible, and so is anything generated at build time and committed, which
      # reads as ordinary code because by then it is. It cannot judge whether a given macro
      # is a public convention or a private one — the tree scoping draws that line, and the
      # scoping is a judgement nobody checks.
      #
      # @example
      #   # bad — the method a reader greps for does not exist in the source
      #   FIELDS.each { |field| define_method(field) { @row[field] } }
      #
      #   # bad
      #   class_eval "def #{name}; @#{name}; end"
      #   def method_missing(name, *args) = @row[name]
      #
      #   # good — greppable, and the reader is done in one line
      #   def reference = @reference
      class NoGeneratedInterfaces < Base
        include ReadsKinds

        DEFINERS = %i[define_method define_singleton_method].freeze
        EVALUATORS = %i[class_eval module_eval instance_eval eval instance_variable_set const_set].freeze
        DISPATCH = %i[method_missing respond_to_missing?].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)

          if DEFINERS.include?(node.method_name)
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
