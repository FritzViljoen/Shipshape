# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-type-suffix`.
      class NoTypeSuffix < Base
        include ReadsKinds

        SUFFIX = /(?:Service|Manager|Interactor|Handler|Command|Query|Workflow)\z/.freeze

        def on_class(node)
          return unless one_of?(governed_kinds)

          name = node.identifier.children.last.to_s
          return if base_class?(name)
          return unless (match = SUFFIX.match(name))

          add_offense(node.identifier, message: message_for(name, match[0]))
        end

        private

        # The suffix names a base class this gem itself installs — `Command`, `IoQuery`,
        # `LegacyCommand` — so the base class's own definition is not an offence against a
        # rule about restating a base class.
        def base_class?(name)
          governed_kinds.flat_map { |kind| Array(settings.base_classes[kind]) }.include?(name)
        end

        def message_for(name, suffix)
          explain(
            "`#{name}` ends in `#{suffix}`, and the base class already says so.",
            because: "The suffix restates what `< #{suffix}` (or whichever base class this " \
                     "operation actually has) already declares below it. The two copies can " \
                     "disagree: a class reworked from a Command into a Workflow keeps a name " \
                     "promising the shape it no longer has, or a rename for what the class " \
                     "now does leaves an old suffix nobody remembered to drop. A reader " \
                     "trusts the name and gets whichever copy is stale.",
            instead: SHAPE,
          )
        end

        SHAPE = <<~RUBY
          # the base class says what kind of thing this is; the name says what it does
          class SettleInvoice < Command
            def call
              ...
            end
          end
        RUBY

        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow command query io_command io_query shape legacy_command legacy_query],
          )
        end
      end
    end
  end
end
