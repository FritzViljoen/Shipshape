# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-comment-is-a-second-copy`.
      class CommentBudget < Base
        include Explains

        MAX = 10

        # One line, always: a file too small for a tenth of a line can still say what it is.
        FLOOR = 1

        # Addressed to the tool, not the reader: a magic comment and a `rubocop:` directive are
        # both machinery, and neither is prose anybody has to keep true.
        DIRECTIVE = /\A#\s*(frozen_string_literal|encoding|warn_indent|shareable_constant_value|rubocop):/.freeze

        def on_new_investigation
          return if processed_source.blank?

          prose = own_line_comments
          budget = [code_lines * max / 100, FLOOR].max
          return if prose.length <= budget

          add_offense(prose.first, message: message_for(prose.length, budget))
        end

        private

        # A trailing comment costs the reader nothing extra — the line was already there.
        def own_line_comments
          processed_source.comments.select do |comment|
            text = comment.text
            !text.match?(DIRECTIVE) && lines[comment.loc.line - 1].lstrip.start_with?("#")
          end
        end

        def code_lines
          lines.count { |line| !line.strip.empty? } - own_line_comments.length
        end

        def lines
          processed_source.lines
        end

        def max
          cop_config.fetch("Max", MAX)
        end

        def message_for(found, budget)
          explain(
            "#{found} comment lines against a budget of #{budget}.",
            because: "A comment is a second copy of a rule, and the copy is the one that " \
                     "goes on being believed after the rule it paraphrases has moved. " \
                     "Nobody reviews it, because nothing points at it when the rule " \
                     "changes. Three shipped in this gem were already false when this cop " \
                     "was written.",
            instead: <<~RUBY
              # The reasoning lives in the law, where it is reviewed when the law changes.
              # What stays here is the clause that names it.

              # Holds `a-command-is-one-transaction`, opened here rather than in each subclass.
              class Command
              end
            RUBY
          )
        end
      end
    end
  end
end
