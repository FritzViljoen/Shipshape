# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/kinds"
require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `the-call-graph-is-declared`.
      class CallGraph < Base
        include Explains
        # No kind calls a sister, and every kind is its own sister. One rule, not a row anyone
        # maintains: a sister call is how a class quietly becomes the kind above it.
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
          class SettleInvoice < Deed
            def call
              invoice = FindInvoice.call(id: @id).value   # a question, one level down
              InvoiceRecord.find(invoice.id).update!(...) # a record, the level below that
            end
          end
        RUBY

        RECORD_COUPLING_ENV = "SHIPSHAPE_RECORD_COUPLING"
        COUPLING_MESSAGE = "(internal, read by Shipshape::Coupling - not a real offence) " \
                           "a call between two governed kinds -> "
        GOVERNED_MESSAGE = "(internal, read by Shipshape::Coupling - not a real offence) " \
                           "this file is a governed caller."

        # Arriving under governance is a change in the map, never a call - `Coupling` reads this.
        def on_new_investigation
          return unless ENV[RECORD_COUPLING_ENV]
          return if processed_source.blank? || kind_of_inspected_file.nil?

          add_offense(marker_range, message: GOVERNED_MESSAGE, severity: :info)
        end

        def on_send(node)
          receiver = node.receiver
          return unless receiver && receiver.const_type?

          caller_kind = kind_of_inspected_file
          return if caller_kind.nil?

          name = constant_name(receiver)
          return if refers_to_itself?(name)

          callee_kind = kinds.for_constant(name)
          return if callee_kind.nil?

          record_coupling(node, name)

          return if allowed?(caller_kind, callee_kind)

          add_offense(receiver, message: message_for(caller_kind, callee_kind))
        end

        alias on_csend on_send

        private

        def record_coupling(node, name)
          return unless ENV[RECORD_COUPLING_ENV]

          add_offense(node, message: "#{COUPLING_MESSAGE}#{kinds.relative_file_for_constant(name)}", severity: :info)
        end

        # Zero-length, at EOF: `add_offense` dedupes by range, and a first-byte `C.call` used to claim (0, 1) and swallow the real offence.
        def marker_range
          length = processed_source.buffer.source.length
          Parser::Source::Range.new(processed_source.buffer, length, length)
        end

        # Refused before the matrix is consulted, so no configuration can permit one.
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
                       "Two deeds always done together are one deed, run as a workflow " \
                       "that never said so; two questions always composed together are " \
                       "one question's reads, run as the N+1 nobody meant to write. " \
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

        def named(kind)
          article = kind.to_s.start_with?("a", "e", "i", "o", "u") ? "an" : "a"

          "#{article} #{kind}"
        end

        # A class naming itself is not a call between two of a kind.
        def refers_to_itself?(name)
          own_superclass?(name) || own_file?(name)
        end

        def own_file?(name)
          resolved = kinds.file_for_constant(name)
          return false if resolved.nil?

          File.expand_path(resolved) == File.expand_path(processed_source.file_path)
        end

        # A parent is not a sister: `ApplicationRecord.transaction` inside a record names the
        # class it inherits from, and refusing it as a record calling a record would report the
        # offence in words that are untrue.
        def own_superclass?(name)
          superclass = kinds.superclass_of(processed_source.file_path)

          !superclass.nil? && superclass.sub(/\A::/, "") == name
        end

        def kind_of_inspected_file
          kinds.for_path(processed_source.file_path)
        end

        # A relative constant resolving through an enclosing namespace is skipped, not guessed.
        def constant_name(node)
          node.source.sub(/\A::/, "")
        end

        def kinds
          @kinds ||= ::Shipshape::Kinds.new(settings: settings, base_dir: base_dir)
        end

        def settings
          @settings ||= ::Shipshape::Settings.from_cop_config(cop_config)
        end

        # From the configuration that loaded this cop, never `Dir.pwd`: resolving from the
        # working directory silently matches nothing when RuboCop runs in a subdirectory.
        def base_dir
          config.base_dir_for_path_parameters
        end
      end
    end
  end
end
