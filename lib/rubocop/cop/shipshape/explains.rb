# frozen_string_literal: true

module RuboCop
  module Cop
    module Shipshape
      # THE MESSAGE IS THE DOCUMENTATION.
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
