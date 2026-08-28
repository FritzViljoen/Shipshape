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
      ([heading] + [summary] + [where_to_start] + detail).join("\n")
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
        "| #{row.title} | #{row.count} | #{ratio(row)} | `#{row.law}` |"
      end

      (["| What | Found | Already right | Law |", "|---|---:|---:|---|"] + rows).join("\n") + "\n"
    end

    def ratio(row)
      return "—" if row.share.nil?

      "#{row.clean} of #{row.population} #{row.noun} (#{row.share}%)"
    end

    # THE ONE SECTION A READER WHO ALREADY KNOWS THE CODEBASE NEEDS.
    #
    # Twelve lists of findings tell a CTO what they knew: the big files are big. What they
    # cannot see by reading down the page is that one file appears in eight of the twelve —
    # and that is the whole answer to "what do we do first", sitting in the report unsaid.
    #
    # Ranked by how many DIFFERENT measures a file appears in rather than by how many
    # findings it has, because breadth is what makes a file expensive: a thousand similar
    # findings is one problem, and eight kinds of finding is eight.
    def where_to_start
      worst = concentration.first(10)
      return "" if worst.empty?

      lines = ["## Where to start", "", <<~TEXT.chomp, ""]
        These files appear in the most measures. Ranked by how many different kinds of
        finding they carry, not how many findings — a thousand of one kind is one problem,
        and six kinds is six.
      TEXT

      (lines + worst.map { |path, measures| "- `#{path}` — #{measures.length} of #{report[:rows].length}: #{measures.join(", ").downcase}" } + [""]).join("\n")
    end

    def concentration
      found = Hash.new { |hash, key| hash[key] = [] }

      report[:rows].each do |row|
        row.findings.map(&:relative).uniq.each { |path| found[path] << row.title }
      end

      found.sort_by { |path, measures| [-measures.length, path] }
    end

    def detail
      report[:rows].map { |row| section(row) }
    end

    def section(row)
      lines = ["## #{row.title} — #{row.count}", "", row.why, ""]
      lines += [row.headline, ""] if row.headline
      lines += ["> **What this cannot see:** #{row.caveat}", ""] if row.caveat
      lines += row.count.zero? ? ["Nothing found.", ""] : examples_for(row)
      lines += ["### What it could look like", "", row.proposal, ""] if row.proposal
      lines += already_right(row) if row.exemplars.any?

      lines.join("\n")
    end

    # Their own code, doing it right. Every codebase has some, and holding it up is what
    # turns a diagnostic from a verdict into a direction — the shape being asked for is
    # already in the repository, written by the same people.
    def already_right(row)
      ["### Where it is already right", ""] +
        row.exemplars.first(2).map { |finding| "- `#{finding.relative}:#{finding.line}` #{finding.label}" } +
        [""]
    end

    def examples_for(row)
      shown = row.findings.first(examples).flat_map { |finding| example(finding, source: row.source?) }
      # Saying how many were not shown, rather than trailing off, because a truncated list
      # that does not admit it reads as the whole list.
      shown << "- …and #{row.count - examples} more" if row.count > examples

      shown + [""]
    end

    # The line itself, under the reference. A file and a line number ask the reader to go
    # and look; the code asks nothing and is usually enough to decide whether to.
    #
    # NOT FOR A CLASS DECLARATION, though. `app/models/booking.rb:3` followed by
    # `class Booking < ApplicationRecord` is the same word twice and a reference to nothing
    # the reader did not have — the stutter moved rather than left. A measure whose findings
    # ARE classes says so, and its examples carry the count instead.
    # A FINDING NEVER RENDERS AS A BARE PATH. That is the whole rule, and it decides both
    # ways: where the label already carries the point, the source line is redundant and is
    # left out; where there is no label, the line is all the reader has and it is shown —
    # `offered_services_presenter.rb:70` says nothing at all about which of the three
    # classes in that file is meant.
    def example(finding, source: true)
      labelled = finding.label.to_s != ""
      line = ["- `#{finding.relative}:#{finding.line}`#{" #{finding.label}" if labelled}"]
      code = source || !labelled ? source_line(finding) : nil

      code ? line + ["  `#{code}`"] : line
    end

    def source_line(finding)
      path = File.join(report[:root], finding.relative)
      return nil unless File.file?(path)

      @lines ||= {}
      @lines[path] ||= File.readlines(path)
      @lines[path][finding.line - 1]&.strip
    rescue StandardError
      nil
    end
  end
end
