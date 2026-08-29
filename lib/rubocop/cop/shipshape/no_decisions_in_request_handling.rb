# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the checkable half of `no-decisions-in-request-handling`.
      #
      # An instance variable in a controller is what the action is about to render. A
      # predicate sent to one is the action interrogating its own payload and acting on the
      # answer — a rule with two owners, in the one file nobody greps for business logic.
      #
      # `if result.success?` is allowed: the decision was made by the operation and came back
      # as a value. `if request.xhr?` is allowed: a property of the call being served.
      #
      # WHAT IT DOES NOT CATCH: a decision on a local rather than an instance variable, and a
      # branch on something the action computed itself. It is the mechanical part of a rule
      # that is otherwise a judgement — the rest is held by review, and the law says so.
      #
      # @example
      #   # bad
      #   def update
      #     return redirect_to root_path if @booking.cancelled?
      #   end
      #
      #   # good — the command answers, the action places
      #   def update
      #     result = CancelBooking.call(id: integer_param!(:id))
      #
      #     if result.success?
      #       redirect_to bookings_path
      #     else
      #       render :edit, status: :unprocessable_entity
      #     end
      #   end
      class NoDecisionsInRequestHandling < Base
        include ReadsKinds

        OUTCOMES = %i[success? failure? success failure].freeze

        def on_if(node)
          return unless one_of?(handling_kinds)

          asks(node.condition).each { |ask| add_offense(ask, message: message_for(ask)) }
        end
        alias on_case on_if

        private

        def message_for(ask)
          subject = ask.receiver.source

          explain(
            "`#{subject}` is what this action is about to render, and asking it " \
            "`#{ask.method_name}` decides something on its behalf.",
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
