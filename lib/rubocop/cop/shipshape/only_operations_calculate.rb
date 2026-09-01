# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `only-an-operation-calculates`.
      class OnlyOperationsCalculate < Base
        include ReadsKinds

        ARITHMETIC = %i[+ - * / %].freeze

        # Ordering only. `==` between two reads is identity — `row.id == @selected_id` — which
        # is placement, and refusing it would refuse the commonest correct line in a template.
        THRESHOLD = %i[< > <= >=].freeze

        TOTALS = %i[sum inject reduce].freeze

        # A value the author wrote down rather than one the class was handed. One of these on
        # either side makes the expression an offset or a configured threshold, not a rule.
        LITERALS = %i[int float str sym array hash true false nil dstr regexp const].freeze

        # `+` and `-` over these assemble a list; they answer no question an operation could
        # have answered instead.
        COLLECTIONS = %i[map flat_map collect values keys to_a entries flatten compact uniq
                         select reject sort sort_by pluck wrap].freeze

        def on_send(node)
          return unless one_of?(governed_kinds)

          if ARITHMETIC.include?(node.method_name) && node.arguments.one?
            add_offense(node, message: derives(node)) if between_reads?(node)
          elsif THRESHOLD.include?(node.method_name) && node.arguments.one?
            add_offense(node, message: answers(node)) if between_reads?(node)
          elsif TOTALS.include?(node.method_name) && node.receiver
            add_offense(node, message: totals(node.method_name))
          end
        end

        private

        def between_reads?(node)
          return false unless node.receiver
          return false if literal?(node.receiver) || literal?(node.first_argument)

          !collection?(node.receiver) && !collection?(node.first_argument)
        end

        def collection?(node)
          node.respond_to?(:send_type?) && node.send_type? && COLLECTIONS.include?(node.method_name)
        end

        def literal?(node)
          return true if node.nil?
          return true if LITERALS.include?(node.type)

          # `30.days` is a number wearing a method, and still a number. Only numeric receivers:
          # `Money.new(1)` is data.
          node.send_type? && node.receiver && %i[int float].include?(node.receiver.type)
        end

        def derives(node)
          explain(
            "`#{one_line(node)}` works out a new value here.",
            because: "A derivation is a rule, and a rule has one home. Written here it has two " \
                     "owners — this file and whichever operation already answers the same " \
                     "question — and the copy nobody greps for is the one that goes stale. " \
                     "This layer translates a value a reader can read and decides where it " \
                     "goes; anything that turns inputs into a new value belongs upstream, in " \
                     "the operation that owns the number.",
            instead: SHAPE,
          )
        end

        def answers(node)
          explain(
            "`#{one_line(node)}` answers a domain question here.",
            because: "A threshold is a rule wearing a comparison: `ends_at < @now` is the " \
                     "definition of \"past\", decided at the point of rendering rather than by " \
                     "whoever owns what past means. The next caller will spell it differently " \
                     "and neither will be wrong. Have the query answer it and carry the answer " \
                     "as a field.",
            instead: SHAPE,
          )
        end

        def totals(method)
          explain(
            "`#{method}` totals a collection here.",
            because: "A total is an operation's answer. Computed at render time it is " \
                     "recomputed at every render, it cannot be tested without the template, " \
                     "and a second screen showing the same figure will work it out again — " \
                     "which is how two totals of one thing come to disagree.",
            instead: SHAPE,
          )
        end

        SHAPE = <<~RUBY
          # the query works the answer out and hands it over as a field
          class ListInvoiceLines < Query
            def call
              lines.map { |line| Line.new(total: line.units * line.rate) }
            end
          end

          # the component places it and does not check it
          def total
            @line.total
          end
        RUBY

        def one_line(node)
          source = node.source.tr("\n", " ").squeeze(" ")

          source.length > 60 ? "#{source[0, 57]}..." : source
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[view_component request_handling entry_point shape])
        end
      end
    end
  end
end
