# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds the rescue half of `no-silent-coercion`.
      #
      # **The failure mode is not the unknown error; it is the known error, swallowed.** Yuan
      # et al. found 92% of catastrophic failures in production distributed systems came from
      # mishandling errors that had already been signalled — and that a third of those were
      # trivial: an empty handler, a bare log, a `TODO`.
      #
      # WHAT IT DOES NOT CATCH: a **predicate** rescuing to `true` or `false` is exempt —
      # there the literal is the answer, not a default, because the question had exactly two
      # outcomes and the failure produced one of them. "Only logs" is a **closed list** of
      # logger receivers. A rescue that swallows by returning a computed value rather than
      # a literal is invisible, and that is the hardest case, not the rarest.
      #
      # @example
      #   # bad — the error was signalled, and this is where it stopped
      #   rescue StandardError
      #   end
      #
      #   # bad — a log is not a handler; nothing downstream knows
      #   rescue StandardError => e
      #     Rails.logger.error(e)
      #   end
      #
      #   # good — an expected failure comes back as a value the caller can act on
      #   rescue Supplier::Rejected => e
      #     failure(:supplier_rejected, detail: e.message)
      #   end
      class NoEmptyRescue < Base
        include Explains

        LOGGERS = %w[logger Rails.logger Rails].freeze
        LOG_LEVELS = %i[debug info warn error fatal log].freeze

        def on_resbody(node)
          body = node.body

          return if answering_a_predicate?(node, body)

          reason =
            if body.nil? then "is empty"
            elsif only_logs?(body) then "only logs"
            elsif literal?(body) then "only returns `#{body.source}`"
            end
          return unless reason

          add_offense(node, message: message_for(reason))
        end

        private

        # `def repository?; run("rev-parse"); true; rescue Error; false; end`
        #
        # The one shape where a literal is the answer rather than a default. A predicate has
        # exactly two answers, and the failure produces one of them — nothing is swallowed,
        # because there was no other outcome the caller was waiting for. Ruby offers no
        # other way to write it, which is why this is a clause rather than a code change.
        def answering_a_predicate?(node, body)
          return false unless body
          return false unless %i[true false].include?(body.type)

          node.each_ancestor(:def, :defs).any? { |definition| definition.method_name.to_s.end_with?("?") }
        end

        def only_logs?(body)
          statements = body.begin_type? ? body.children : [body]
          statements.all? { |statement| log?(statement) }
        end

        def log?(node)
          return false unless node.respond_to?(:send_type?) && node.send_type?
          return false unless LOG_LEVELS.include?(node.method_name)

          LOGGERS.include?(node.receiver&.source.to_s)
        end

        def literal?(body)
          %i[nil false true int float str sym array hash].include?(body.type)
        end

        def message_for(reason)
          explain(
            "This rescue #{reason}, so a failure that was signalled stops here.",
            because: "The dangerous failure is not the unknown error — it is the known " \
                     "error, swallowed. Yuan et al. (OSDI 2014) found 92% of catastrophic " \
                     "failures in production distributed systems came from mishandling " \
                     "errors that had already been signalled, and a third of those were " \
                     "an empty handler, a bare log, or a TODO. The caller now proceeds on " \
                     "a value that was never produced.",
            instead: <<~RUBY,
              # a defect raises: it is nobody's answer, and the stack trace is the point
              # an expected failure comes back as a value the caller can act on
              def call
                success(@gateway.charge(@amount))
              rescue Supplier::Rejected => e
                failure(:supplier_rejected, detail: e.message)
              end

              # at the call site, the only branch request handling is allowed
              if result.success?
                redirect_to receipt_path(result.value)
              else
                render :new, status: :unprocessable_entity
              end
            RUBY
          )
        end
      end
    end
  end
end
