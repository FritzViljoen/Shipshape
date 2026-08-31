# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the checkable half of `no-decisions-in-request-handling`.
      class NoDecisionsInRequestHandling < Base
        include ReadsKinds

        OUTCOMES = %i[success? failure? success failure].freeze

        # `if @booking.save` is the commonest shape here, and calling it "asking" was wrong:
        # it writes, and then branches on whether the write worked. Messages are the
        # documentation, so they have to be accurate about what the code does.
        WRITES = %i[save save! update update! update_attributes destroy destroy! create create!
                    toggle touch increment decrement].freeze

        def on_if(node)
          return unless one_of?(handling_kinds)

          asks(node.condition).each { |ask| add_offense(ask, message: message_for(ask)) }
        end
        alias on_case on_if

        private

        def message_for(ask)
          subject = ask.receiver.source
          verb = if WRITES.include?(ask.method_name)
                   "writing through it with `#{ask.method_name}` and branching on the result " \
                     "puts the write and the decision here"
                 else
                   "asking it `#{ask.method_name}` decides something on its behalf"
                 end

          explain(
            "`#{subject}` is what this action is about to render, and #{verb}.",
            because: "The rule now has two owners — this action and whatever else asks the " \
                     "same question — and they will disagree. Nobody greps a controller for " \
                     "business logic, so the copy here is the one that goes stale.",
            instead: <<~RUBY,
              result = SomeCommand.call(...)   # answers success(...) or failure(:code)

              if result.success?               # placing, not deciding
                redirect_to somewhere_path
              else
                render :show, status: :unprocessable_entity
              end
            RUBY
          )
        end

        # A predicate sent to an instance variable, at any depth of the condition.
        def asks(test)
          found = []
          walk(test) do |node|
            next unless node.send_type? && node.receiver
            next unless node.receiver.ivar_type?
            next if OUTCOMES.include?(node.method_name)

            found << node
          end
          found
        end

        def walk(node, &block)
          return unless node.is_a?(RuboCop::AST::Node)

          block.call(node)
          node.children.each { |child| walk(child, &block) }
        end

        def handling_kinds
          cop_config.fetch("Kinds", %w[request_handling entry_point])
        end
      end
    end
  end
end
