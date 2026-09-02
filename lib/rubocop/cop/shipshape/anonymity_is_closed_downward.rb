# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-permission-is-the-class-name`.
      class AnonymityIsClosedDownward < Base
        include ReadsKinds

        RUNS = %i[call call_later].freeze
        KINDS = %w[workflow write read io_write io_read legacy_write legacy_read].freeze

        CLOSED = <<~RUBY
          # what an anonymous operation reaches is anonymous too, so nothing guarded runs
          # without somebody having been asked
          class LogIn < Write
            def anonymous_call
              FindPersonByEmail.call(email: @email)
            end
          end

          # and where the work genuinely needs a grant, the caller is the one that holds it:
          # this operation implements `call`, takes an actor, and aggregates what it reaches
        RUBY

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

        def guarded?(name)
          return false unless step_kinds.include?(kinds.for_constant(name))

          path = kinds.file_for_constant(name)
          return false unless path

          !declares_anonymous_call?(path, name.split("::").last)
        end

        # The callee class's own body, never the file's text: matching the whole file let a
        # second class in it answer for the one being called.
        def declares_anonymous_call?(path, short)
          klass = class_named(path, short)
          return false unless klass&.body

          statements = klass.body.begin_type? ? klass.body.children : [klass.body]
          statements.any? { |statement| statement.def_type? && statement.method_name == :anonymous_call }
        end

        def class_named(path, short)
          source = ::RuboCop::ProcessedSource.new(::Shipshape::SourceText.read(path), RUBY_VERSION.to_f, path)
          return nil unless source.valid_syntax? && source.ast

          [source.ast, *source.ast.each_descendant].find do |node|
            node.class_type? && node.identifier.source.split("::").last == short
          end
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

        # The legacy trees are in both lists: omitting them left the cop blind where laundering
        # is likeliest.
        def step_kinds
          cop_config.fetch("StepKinds", KINDS)
        end

        def governed_kinds
          cop_config.fetch("Kinds", KINDS)
        end
      end
    end
  end
end
