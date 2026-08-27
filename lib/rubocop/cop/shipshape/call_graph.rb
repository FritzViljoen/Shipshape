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
      # NO KIND CALLS ITS OWN KIND, and that rule lives here rather than in the matrix —
      # a row naming itself stops the run. A sister call is how a class quietly becomes
      # the kind above it: a command sequencing commands is a workflow that never said so,
      # a query composing queries is the read that turns into an N+1.
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
        MSG = "%<caller>s may not call %<callee>s. Declared: %<allowed>s."

        MSG_NONE = "%<caller>s may not call anything. " \
                   "Move the work to a caller that may."

        # No kind calls its own kind. This is one rule, not a row anyone maintains: a
        # sister call is the shape by which a class quietly becomes the kind above it —
        # a command sequencing commands is a workflow that never said so, a query
        # composing queries is the read that turns into an N+1.
        MSG_SISTER = "%<caller>s may not call %<callee>s. No kind calls its own kind — " \
                     "sequence them from the kind above."

        MATRIX_ERROR = "Shipshape/CallGraph: Matrix row %<kind>s lists itself. " \
                       "No kind calls its own kind, so a row naming itself is a " \
                       "contradiction rather than a permission."

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

        # The matrix is checked once per run rather than per call site, and a row that
        # names its own kind stops the run instead of being quietly dropped.
        def on_new_investigation
          matrix.each do |kind, reachable|
            raise ValidationError, format(MATRIX_ERROR, kind: kind) if Array(reachable).include?(kind)
          end
        end

        private

        # A sister call is refused before the matrix is consulted, so no configuration can
        # permit one. The matrix says which OTHER kinds are reachable; it is not the place
        # this rule lives.
        def allowed?(caller_kind, callee_kind)
          return false if caller_kind == callee_kind

          Array(matrix[caller_kind]).include?(callee_kind)
        end

        def message_for(caller_kind, callee_kind)
          caller_phrase = named(caller_kind).capitalize
          callee_phrase = named(callee_kind)

          return format(MSG_SISTER, caller: caller_phrase, callee: callee_phrase) if caller_kind == callee_kind

          allowed = Array(matrix[caller_kind])
          return format(MSG_NONE, caller: caller_phrase) if allowed.empty?

          format(MSG, caller: caller_phrase, callee: callee_phrase, allowed: allowed.join(", "))
        end

        # A kind is a configured word, so the article is decided here rather than written
        # into the config beside every name. Vowel-initial only — a kind spelled to defeat
        # that reads a little wrong in one message and nothing else breaks.
        def named(kind)
          article = kind.to_s.start_with?("a", "e", "i", "o", "u") ? "an" : "a"

          "#{article} #{kind}"
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
