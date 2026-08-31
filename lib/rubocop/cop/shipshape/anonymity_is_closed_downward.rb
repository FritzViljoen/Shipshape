# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-permission-is-the-class-name`.
      #
      # An operation implementing `anonymous_call` runs before anyone is identified: no actor,
      # no check. That is a declaration about this class, and it is audited by grep.
      #
      # **It has to be closed downward.** An anonymous operation that calls a guarded one runs
      # that operation for nobody — a login page reaching `ChargeCard` charges the card, and
      # every check the model has was satisfied by the outer declaration. Aggregation closes the
      # loophole one level up; this closes it one level down, and without it the escape hatch
      # for "this read needs no grant" is a way to launder any write.
      #
      # So an `anonymous_call` names anonymous operations, or none at all.
      #
      # WHAT IT DOES NOT CATCH: it resolves the callee to a file and looks for
      # `def anonymous_call` in it, so an operation whose constant resolves to no file — a gem's,
      # or one the layout does not govern — is skipped rather than guessed at. It reads
      # `anonymous_call` only, so an anonymous operation reaching a guarded one through a private
      # helper, a variable or `send` is invisible here, exactly as it is to the base class.
      #
      # It says nothing about whether a class *should* be anonymous. A read declared anonymous
      # that ought to have been granted is unguarded and looks correct; that judgement is the
      # one `grep -rn "def anonymous_call"` exists for.
      #
      # @example
      #   # bad — the login runs a guarded command for nobody
      #   class LogIn < Command
      #     def anonymous_call
      #       ChargeCard.call(actor: nil, amount: @amount)
      #     end
      #   end
      #
      #   # good — anonymity is closed: what it reaches is anonymous too
      #   class LogIn < Command
      #     def anonymous_call
      #       FindPersonByEmail.call(email: @email)
      #     end
      #   end
      class AnonymityIsClosedDownward < Base
        include ReadsKinds

        RUNS = %i[call call_later].freeze
        DECLARATION = /^\s*(?:private\s+)?def\s+anonymous_call\b/.freeze

        def on_def(node)
          return unless node.method_name == :anonymous_call
          return unless one_of?(governed_kinds)

          guarded_calls(node).each { |send| add_offense(send, message: message_for(send.receiver.source)) }
        end

        private

        def guarded_calls(node)
          node.each_node(:send).select do |send|
            next false unless RUNS.include?(send.method_name)

            receiver = send.receiver
            receiver&.const_type? && guarded?(receiver.source.sub(/\A::/, ""))
          end
        end

        # An operation the layout does not govern, or one belonging to a gem, resolves to no
        # file. Guessing there would fail correct code, so it is skipped.
        def guarded?(name)
          return false unless step_kinds.include?(kinds.for_constant(name))

          path = kinds.file_for_constant(name)
          return false unless path

          !DECLARATION.match?(::Shipshape::SourceText.read(path))
        end

        def message_for(name)
          explain(
            "`#{name}` is guarded, and this operation is anonymous.",
            because: "An anonymous operation runs before anyone is identified — no actor, no " \
                     "check — so a guarded operation it calls runs for nobody. Every " \
                     "permission below this line was satisfied by one declaration at the top " \
                     "of this file, which is the laundering that aggregating permissions " \
                     "exists to stop, reopened one level down. Anonymity is a claim about a " \
                     "whole subtree, not about one method.",
            instead: CLOSED,
          )
        end

        CLOSED = <<~RUBY
          # what an anonymous operation reaches is anonymous too, so nothing guarded runs
          # without somebody having been asked
          class LogIn < Command
            def anonymous_call
              FindPersonByEmail.call(email: @email)
            end
          end

          # and where the work genuinely needs a grant, the caller is the one that holds it:
          # this operation implements `call`, takes an actor, and aggregates what it reaches
        RUBY

        def step_kinds
          cop_config.fetch("StepKinds", %w[command query io_command io_query workflow])
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[workflow command query io_command io_query])
        end
      end
    end
  end
end
