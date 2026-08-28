# frozen_string_literal: true

require "shipshape/typed_arguments"

module Shipshape
  # The report, written for somebody to read rather than for a machine to parse.
  #
  # Markdown, because the thing anybody does with a diagnostic is paste it into a document
  # and argue about it — and an argument is the point. Every row names the law it comes from
  # and, where the measure cannot tell one thing from another, says so on the row rather
  # than in a footnote nobody reaches.
  class ReportAsMarkdown
    include TypedArguments

    EXAMPLES = 5

    def initialize(report:, examples: EXAMPLES)
      @report = typed(report, Hash)
      @examples = typed(examples, Integer)
    end

    def call
      ([heading] + [summary] + detail).join("\n")
    end

    private

    attr_reader :report, :examples

    def heading
      <<~TEXT
        # shipshape report

        `#{report[:root]}` — #{report[:files]} Ruby files read under `app/` and `lib/`.

        Nothing here is a bug. Every row is a place where a rule has no home, or has one
        nobody can reach — which is what makes a codebase expensive to change rather than
        wrong.
      TEXT
    end

    def summary
      rows = report[:rows].map do |row|
        "| #{row.title} | #{row.count} | #{row.files} | `#{row.law}` |"
      end

      (["| What | Found | In files | Law |", "|---|---:|---:|---|"] + rows).join("\n") + "\n"
    end

    def detail
      report[:rows].map { |row| section(row) }
    end

    def section(row)
      lines = ["## #{row.title} — #{row.count}", "", row.why, ""]
      lines += ["> **What this cannot see:** #{row.caveat}", ""] if row.caveat
      lines += row.count.zero? ? ["Nothing found.", ""] : examples_for(row)

      lines.join("\n")
    end

    def examples_for(row)
      shown = row.findings.first(examples).map { |finding| "- `#{finding.relative}:#{finding.line}` #{finding.label}" }
      # Saying how many were not shown, rather than trailing off, because a truncated list
      # that does not admit it reads as the whole list.
      shown << "- …and #{row.count - examples} more" if row.count > examples

      shown + [""]
    end
  end
end
