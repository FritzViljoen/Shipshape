# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-schedule-is-a-row`.
      class NothingSchedulesWork < Base
        include Explains

        # `whenever`'s DSL, and the two Sidekiq schedulers. Each declares a cadence in code.
        DECLARATIONS = %i[every recurring].freeze
        SCHEDULERS = %w[Sidekiq::Cron::Job Sidekiq::Scheduler Resque::Scheduler Clockwork].freeze

        ROW = <<~RUBY
          # a stored request, replayed on a cadence. It names a route rather than a class,
          # because a path is a name already promised to the outside and a class name is one
          # refactoring is free to change. `runs_as_id` is NOT NULL, so an unattributed
          # schedule cannot be stored: if nobody will own it, it is not created.
          Scheduling::CreateSchedule.call(
            actor:      actor,
            method:     "POST",
            path:       "/invoices/settle",
            params:     { tenant_id: tenant.id },
            cadence:    "0 3 * * *",
            runs_as_id: treasurer.id,
          )
        RUBY

        def on_send(node)
          return unless declaration?(node) || scheduler?(node)

          add_offense(node, message: message_for(node.method_name))
        end

        private

        # `every 1.day do ... end` — a bare send with a block, at the top level of a file that
        # is not otherwise governed. A local method called `every` on an explicit receiver is
        # somebody else's.
        def declaration?(node)
          DECLARATIONS.include?(node.method_name) && node.receiver.nil? && node.block_node
        end

        def scheduler?(node)
          receiver = node.receiver
          receiver&.const_type? && SCHEDULERS.include?(receiver.source.sub(/\A::/, ""))
        end

        def message_for(name)
          explain(
            "`#{name}` declares a cadence in code, and a schedule is a row.",
            because: "A schedule is a controller action called at a set frequency — something " \
                     "arrives, an actor is established, one deed runs. Declared in code it " \
                     "has no actor, so the work runs under nobody's name: nothing can say who " \
                     "authorised it, revoking a person does not stop what they set running, " \
                     "and the audit trail answers `system` to the only question worth asking " \
                     "at 3am. A row answers all of it by being data, and adding a schedule " \
                     "stops being a deploy.",
            instead: ROW,
          )
        end
      end
    end
  end
end
