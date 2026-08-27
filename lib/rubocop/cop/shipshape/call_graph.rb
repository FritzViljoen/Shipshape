# frozen_string_literal: true

require "shipshape/kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `the-call-graph-is-declared` (docs/laws/the-call-graph-is-declared.md).
      #
      # Every class has a kind, taken from where it is filed. The kinds that may call each
      # other are declared once, as a matrix, in `Matrix`. A call whose (caller kind,
      # callee kind) pair is absent from the matrix is an offence.
      #
      # This is the load-bearing guard of the canon: a rule cannot escape its home if there
      # is nowhere reachable to escape to. It is what stops a call sideways into a sibling
      # area, or upward out of a record, becoming the first instance of a convention
      # nothing yet forbids.
      #
      # WHAT IT DOES NOT CATCH, and the law says so too:
      #
      # - It resolves receivers **syntactically**. A call through a local assigned earlier,
      #   through a method that returns a collaborator, through `send`, or through any
      #   metaprogrammed dispatch, is invisible.
      # - A constant it cannot resolve to a file under a declared kind is **skipped**, not
      #   failed. Skipping is the safe direction, and it is also how coverage stops growing
      #   without anyone noticing, which is why `shipshape check` reports the count.
      #
      # @example
      #   # bad — a record reaching up into an operation
      #   class PersonRecord < ApplicationRecord
      #     def rank
      #       CalculateStandings.call(people: [self])
      #     end
      #   end
      #
      #   # good — the operation reaches down into the record
      #   class CalculateStandings < Operation
      #     def call
      #       PersonRecord.all
      #     end
      #   end
      class CallGraph < Base
        MSG = "A %<caller_kind>s may not call a %<callee_kind>s. " \
              "Declared: %<allowed>s."

        MSG_NONE = "A %<caller_kind>s may not call anything. " \
                   "Move the work to a caller that may."

        def on_send(node)
          receiver = node.receiver
          return unless receiver && receiver.const_type?

          caller_kind = kind_of_inspected_file
          return if caller_kind.nil?

          callee_kind = kinds.for_constant(constant_name(receiver))
          return if callee_kind.nil?
          return if allowed?(caller_kind, callee_kind)

          add_offense(receiver, message: message_for(caller_kind, callee_kind))
        end
        alias on_csend on_send

        private

        def allowed?(caller_kind, callee_kind)
          Array(matrix[caller_kind]).include?(callee_kind)
        end

        def message_for(caller_kind, callee_kind)
          allowed = Array(matrix[caller_kind])
          return format(MSG_NONE, caller_kind: caller_kind) if allowed.empty?

          format(MSG, caller_kind: caller_kind, callee_kind: callee_kind, allowed: allowed.join(", "))
        end

        def kind_of_inspected_file
          kinds.for_path(processed_source.file_path)
        end

        # `::Geography::ListPlaces` and `Geography::ListPlaces` name one thing. A relative
        # constant that resolves through an enclosing namespace does not, and is why an
        # unresolvable name is skipped rather than guessed at.
        def constant_name(node)
          node.source.sub(/\A::/, "")
        end

        def kinds
          @kinds ||= ::Shipshape::Kinds.new(
            globs_by_kind: cop_config.fetch("Kinds", {}),
            base_dir: base_dir,
          )
        end

        def matrix
          @matrix ||= cop_config.fetch("Matrix", {})
        end

        # Resolved from the configuration that loaded this cop, never from `Dir.pwd`: a cop
        # that resolves paths from the working directory silently stops matching anything
        # when RuboCop is run from a subdirectory, and reports zero offences while doing it.
        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
