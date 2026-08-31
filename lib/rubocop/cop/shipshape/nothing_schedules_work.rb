# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-schedule-is-a-row`.
      #
      # A schedule is a controller action called at a set frequency: something outside arrives,
      # an actor is established, one command runs. The caller being a clock rather than a
      # browser earns no second mechanism, so the schedule is a row — which command, what
      # arguments, how often, and as whom — with the actor a `NOT NULL` column.
      #
      # A cadence declared in code has none of that. Nothing can ask it what runs
      # automatically, nothing can ask whose authority it runs under, and nothing can grant,
      # revoke or audit an entry. It is work that starts by itself, under nobody's name.
      #
      # WHAT IT DOES NOT CATCH: **it reads the application, and a crontab is not in the
      # application.** A schedule in `/etc/cron.d`, a Kubernetes `CronJob`, a cloud scheduler
      # or a CI configuration is invisible here — and those are where the worst ones live,
      # usually as a `rails runner` invocation that steps around every door at once. This
      # removes the in-repository ways of saying it and cannot reach the others.
      #
      # It knows the scheduling libraries by name, so a wrapper of your own is not matched, and
      # a cron expression assembled from parts is not matched. A string that merely looks like
      # a cron expression, in a comment or a test fixture, is not read as one either — only an
      # assignment to a constant is.
      #
      # @example
      #   # bad — a cadence in code: no actor, nothing to grant, nothing to audit
      #   every 1.day, at: "3:00 am" do
      #     runner "SettleOverdueInvoices.call"
      #   end
      #
      #   # bad — the same thing, in a different library
      #   Sidekiq::Cron::Job.create(name: "settle", cron: "0 3 * * *", class: "SettleJob")
      #
      #   # bad — a cadence hidden in a constant
      #   NIGHTLY = "0 3 * * *"
      #
      #   # good — a stored request: a route, a cadence, and the actor it runs as
      #   Scheduling::CreateSchedule.call(
      #     actor: actor,
      #     path: "/invoices/settle",
      #     cadence: "0 3 * * *",
      #     runs_as_id: treasurer.id,
      #   )
      class NothingSchedulesWork < Base
        include Explains

        # `whenever`'s DSL, and the two Sidekiq schedulers. Each declares a cadence in code.
        DECLARATIONS = %i[every recurring].freeze
        SCHEDULERS = %w[Sidekiq::Cron::Job Sidekiq::Scheduler Resque::Scheduler Clockwork].freeze

        # Five fields of cron, loosely: enough to catch `0 3 * * *` and `*/15 * * * *`, and
        # not so loose that a date format or a path matches.
        CRON = /\A[\d*\/,\-]+(?: +[\d*\/,\-]+){4}\z/.freeze

        def on_send(node)
          return unless declaration?(node) || scheduler?(node)

          add_offense(node, message: message_for(node.method_name))
        end

        # A cadence does not stop being one for sitting in a constant, and this is the shape a
        # codebase reaches for once the DSL has been removed.
        def on_casgn(node)
          value = node.children[2]
          return unless value&.str_type?
          return unless CRON.match?(value.value)

          add_offense(node, message: message_for(node.children[1]))
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
                     "arrives, an actor is established, one command runs. Declared in code it " \
                     "has no actor, so the work runs under nobody's name: nothing can say who " \
                     "authorised it, revoking a person does not stop what they set running, " \
                     "and the audit trail answers `system` to the only question worth asking " \
                     "at 3am. A row answers all of it by being data, and adding a schedule " \
                     "stops being a deploy.",
            instead: ROW,
          )
        end

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
      end
    end
  end
end
