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
      # WHAT IT DOES NOT CATCH — in both directions, and this is the canon's weakest guard:
      # it fires on **any** message sent to an instance variable in a condition, not only a
      # predicate, so `render :empty if @report.rows.empty?` is an offence to be argued in
      # review rather than a defect. And a decision on a local, on a method call, or on a
      # plain value it cannot trace is invisible. Data access is a different cop:
      # `Shipshape/CallGraph` refuses request handling an edge to a record, and only for a
      # constant receiver.
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
