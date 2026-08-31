# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the checkable half of `no-decisions-in-request-handling`.
      class NoDecisionsInRequestHandling < Base
        include ReadsKinds

        # The two questions this layer may ask, and the only two. `success?` is a command's
        # outcome; `present?` is whether a query found anything, and it answers correctly for
        # all three legal answers — `nil` and `[]` are absent, a shape and an array are present.
        PERMITTED = %i[success? present?].freeze

        # `if @booking.save` is the commonest shape here, and calling it "asking" was wrong:
        # it writes, and then branches on whether the write worked. Messages are the
        # documentation, so they have to be accurate about what the code does.
        WRITES = %i[save save! update update! update_attributes destroy destroy! create create!
                    toggle touch increment decrement].freeze

        def on_if(node)
          return unless one_of?(handling_kinds)
          return if permitted?(node.condition)

          asked = asks(node.condition)
          return asked.each { |ask| add_offense(ask, message: message_for(ask)) } if asked.any?

          add_offense(node.condition, message: only_two)
        end
        alias on_case on_if

        private

        # `unless` and `!` spell the same branch, and the rule is about what is tested.
        def permitted?(test)
          return false unless test.respond_to?(:send_type?) && test.send_type?
          return permitted?(test.receiver) if test.method?(:!)

          PERMITTED.include?(test.method_name)
        end

        def only_two
          explain(
            "This layer tests `success?` and `present?`, and nothing else.",
            because: "Every other question is a rule, and a rule asked here has two owners — " \
                     "this action and whatever else asks it — which will disagree. Nobody " \
                     "greps a controller for business logic, so the copy here is the one that " \
                     "goes stale. An outcome arrives as a value; the action places a response " \
                     "for each one and reads straight down.",
            instead: <<~RUBY,
              if SettleInvoice.call(id: integer_param!(:id)).success?
                redirect_to invoices_path
              else
                render :show, status: :unprocessable_entity
              end

              if FindInvitation.call(code: text_param!(:code)).present?
                render :invited
              else
                redirect_to signup_path
              end
            RUBY
          )
        end

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

        # Reported in its own words: the commonest shape, and the message teaches more.
        def asks(test)
          found = []
          walk(test) do |node|
            next unless node.send_type? && node.receiver
            next unless node.receiver.ivar_type?
            next if PERMITTED.include?(node.method_name)

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
