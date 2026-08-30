# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/kinds"
require "rubocop/cop/shipshape/explains"

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
        include Explains
        # No kind calls a sister, and every kind is its own sister. One rule, not a row
        # anyone maintains: a sister call is the shape by which a class quietly becomes
        # the kind above it — a command sequencing commands is a workflow that never said
        # so, a query composing queries is the read that turns into an N+1. A legacy
        # command is a command that wraps something old, so it is a sister too.
        SISTERS = <<~RUBY
          # the kind above sequences them, and the sequence is readable in one place
          class SettleMonth < Workflow
            def call
              CloseInvoices.call(month: @month)
              NotifyCustomers.call(month: @month)
            end
          end
        RUBY

        REACH = <<~RUBY
          # the caller reaches down a level, never sideways or up
          class SettleInvoice < Command
            def call
              invoice = FindInvoice.call(id: @id).value   # a query, one level down
              InvoiceRecord.find(invoice.id).update!(...) # a record, the level below that
            end
          end
        RUBY

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
            return explain(
              "#{caller_phrase} may not call #{callee_phrase}. They are sisters.",
              because: "A sister call is how a class quietly becomes the kind above it. " \
                       "A command sequencing commands is a workflow that never said so, " \
                       "and a query composing queries is the read that turns into an N+1. " \
                       "The sequence belongs one level up, where it can be read at once.",
              instead: SISTERS,
            )
          end

          allowed = settings.reachable_from(caller_kind)

          if allowed.empty?
            return explain(
              "#{caller_phrase} may not call anything.",
              because: "It is the bottom of the graph — a shape holds data and a record " \
                       "is a table. Behaviour here is reachable from everywhere the " \
                       "object is, which is how one concern after another settles on it.",
              instead: REACH,
            )
          end

          explain(
            "#{caller_phrase} may not call #{callee_phrase}. " \
            "Declared: #{allowed.join(', ')}.",
            because: "The call graph is declared, so what reaches what can be read off " \
                     "one file instead of traced through the codebase. An undeclared edge " \
                     "is the one nobody knows about until it forms a cycle.",
            instead: REACH,
          )
        end

        # A kind is a configured word, so the article is decided here rather than written
        # into the config beside every name. Vowel-initial only — a kind spelled to defeat
        # that reads a little wrong in one message and nothing else breaks.
        def named(kind)
          article = kind.to_s.start_with?("a", "e", "i", "o", "u") ? "an" : "a"

          "#{article} #{kind}"
        end

        # A class naming itself is not a call between two of a kind. `Result.success(...)`
        # inside `Result` is one shape, and the call graph has nothing to say about it.
        def refers_to_itself?(name)
          own_superclass?(name) || own_file?(name)
        end

        def own_file?(name)
          resolved = kinds.file_for_constant(name)
          return false if resolved.nil?

          File.expand_path(resolved) == File.expand_path(processed_source.file_path)
        end

        # **A parent is not a sister.** `ApplicationRecord.transaction` inside a record names
        # the class it inherits from, and once a declared base class resolves to its kind
        # that read counts as a record calling a record — which the matrix refuses as a
        # sister call. The refusal would be reported in words that are simply untrue, and
        # `enforcement-messages-are-documentation` makes a misleading message a defect in its
        # own right. Whatever is wrong with a record opening a transaction, it is not that.
        def own_superclass?(name)
          superclass = kinds.superclass_of(processed_source.file_path)

          !superclass.nil? && superclass.sub(/\A::/, "") == name
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
