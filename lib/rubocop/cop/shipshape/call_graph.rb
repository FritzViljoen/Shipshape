# frozen_string_literal: true

require "shipshape/settings"
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
      # NO KIND CALLS A SISTER, and that rule lives here rather than in the matrix — a row
      # naming a sister stops the run. Every kind is its own sister, and `Sisters` declares
      # the rest: a legacy command is a command that wraps something old.
      #
      # A sister call is how a class quietly becomes the kind above it: a command
      # sequencing commands is a workflow that never said so, a query composing queries is
      # the read that turns into an N+1.
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

        # No kind calls a sister, and every kind is its own sister. One rule, not a row
        # anyone maintains: a sister call is the shape by which a class quietly becomes
        # the kind above it — a command sequencing commands is a workflow that never said
        # so, a query composing queries is the read that turns into an N+1. A legacy
        # command is a command that wraps something old, so it is a sister too.
        MSG_SISTER = "%<caller>s may not call %<callee>s. They are sisters, and no kind " \
                     "calls a sister — sequence them from the kind above."

        def on_send(node)
          receiver = node.receiver
          return unless receiver && receiver.const_type?

          caller_kind = kind_of_inspected_file
          return if caller_kind.nil?

          name = constant_name(receiver)
          return if refers_to_itself?(name)

          callee_kind = kinds.for_constant(name)
          return if callee_kind.nil?
          return if allowed?(caller_kind, callee_kind)

          add_offense(receiver, message: message_for(caller_kind, callee_kind))
        end

        alias on_csend on_send

        private

        # A sister call is refused before the matrix is consulted, so no configuration can
        # permit one. The matrix says which non-sister kinds are reachable; it is not the
        # place this rule lives.
        def allowed?(caller_kind, callee_kind)
          return false if sisters?(caller_kind, callee_kind)

          settings.reachable_from(caller_kind).include?(callee_kind)
        end

        def sisters?(caller_kind, callee_kind)
          settings.sisters_of(caller_kind).include?(callee_kind)
        end

        def message_for(caller_kind, callee_kind)
          caller_phrase = named(caller_kind).capitalize
          callee_phrase = named(callee_kind)

          if sisters?(caller_kind, callee_kind)
            return format(MSG_SISTER, caller: caller_phrase, callee: callee_phrase)
          end

          allowed = settings.reachable_from(caller_kind)
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

        # A class naming itself is not a call between two of a kind. `Result.success(...)`
        # inside `Result` is one entity, and the call graph has nothing to say about it.
        def refers_to_itself?(name)
          resolved = kinds.file_for_constant(name)
          return false if resolved.nil?

          File.expand_path(resolved) == File.expand_path(processed_source.file_path)
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
          @kinds ||= ::Shipshape::Kinds.new(settings: settings, base_dir: base_dir)
        end

        # Parsed once, at the seam, and asserted there. Everything past this line is handed
        # real values — no `fetch` on a raw config hash, no wondering whether a key is
        # present or spelled right.
        def settings
          @settings ||= ::Shipshape::Settings.from_cop_config(cop_config)
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
