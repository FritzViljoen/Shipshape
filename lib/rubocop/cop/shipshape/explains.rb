# frozen_string_literal: true

module RuboCop
  module Cop
    module Shipshape
      # THE MESSAGE IS THE DOCUMENTATION.
      #
      # A failure is the only thing most readers of a rule will ever see, and for an agent it
      # is the entire context it gets: no session memory, no design document, no colleague to
      # ask. Whatever the message does not say is not known.
      #
      # So every offence carries three parts, and this method is what makes all three
      # unskippable — you cannot call it and leave one out:
      #
      #   1. what is wrong, in this file, naming the thing
      #   2. WHY the rule exists, so it can be reasoned with rather than obeyed
      #   3. INSTEAD, a correct example short enough to copy
      #
      # A cop that says "avoid this" teaches nothing and gets suppressed. One that shows the
      # shape gets followed. `Shipshape/EnforcementMessagesAreDocumentation` holds the rule
      # over the cops themselves — this gem's and yours.
      module Explains
        WHY = "WHY:"
        INSTEAD = "INSTEAD:"

        def explain(problem, because:, instead:)
          [problem, "", "#{WHY} #{because}", "", INSTEAD, indent(instead)].join("\n")
        end

        def indent(code)
          code.strip.lines.map { |line| "    #{line}" }.join.chomp
        end
      end
    end
  end
end
