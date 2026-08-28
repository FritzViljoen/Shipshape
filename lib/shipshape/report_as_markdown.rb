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
      ([heading] + [situation] + [summary] + [where_to_start] + [the_shape] + detail).join("\n")
    end

    private

    attr_reader :report, :examples

    def heading
      <<~TEXT
        # shipshape report

        `#{report[:root]}` — #{report[:files]} Ruby files read under `app/` and `lib/`.
      TEXT
    end

    # WHY ANY OF THIS IS BEING COUNTED.
    #
    # Twelve lists of findings with no argument around them is a tool showing off. A reader
    # who already knows the codebase needs the claim first — what these have in common, what
    # it costs, and what the alternative looks like — or every number reads as a complaint
    # about a decision somebody made for a good reason in 2016.
    def situation
      <<~TEXT

        ## What this is measuring, and why

        **Nothing here is a bug.** Every application below ships, passes its tests and earns
        money. What is being counted is something else: how many places a rule lives where
        nobody would look for it.

        A Rails application starts with three homes — a controller, a model, a view — and
        every rule that does not obviously belong in one of them goes in whichever is
        nearest. A price calculation lands in the controller because that is where the form
        posted. A booking check lands on the record because that is where the data is. Each
        of those is a reasonable decision on the day. **What they add up to is a codebase
        where the answer to "where does this go" is "wherever you are standing", and the
        answer to "where is this" is "read everything".**

        That is what makes a change expensive. Not the size of the codebase — the number of
        places you must read before you can be sure a change is finished.

        **It is worse now than it was, and for a reason that has nothing to do with anybody
        here.** Writing code stopped being the expensive part. Reading it did not. A
        codebase where the rules have no homes is one where neither a new developer nor an
        agent can be handed a task and trusted with it, because neither can tell what a
        change touches. The cost was always there; it used to be paid slowly.

        **Every measure below is one shape of the same thing:** a rule with no home, or a
        home nobody can reach. The counts are not a score. They are a map of where the
        reading is expensive, and the ratio beside each one says how much of the codebase is
        already fine — which is usually most of it.
      TEXT
    end

    # THE DESTINATION, in code.
    #
    # A report that only says what is wrong leaves the reader to invent the alternative, and
    # they will invent the one they already know. Five small classes are enough to show the
    # whole shape, and every proposal further down lands in one of them.
    def the_shape
      <<~TEXT

        ## What the shape is

        Five kinds of class, and every proposal further down becomes one of them. The point
        is not the names — it is that each kind may only reach certain others, so a rule
        cannot end up somewhere nobody would look for it.

        ```ruby
        # A COMMAND is one write, in one transaction. It answers with a Result.
        class SettleInvoice < Command
          def initialize(invoice:, paid_on:)
            @invoice = typed(invoice, Invoice)     # asserted here, and nowhere else
            @paid_on = typed(paid_on, Date)
          end

          def call
            return failure(:already_settled) if @invoice.settled_on          # an expected outcome
            InvoiceRecord.find(@invoice.id).update!(settled_on: @paid_on)    # the one write
            success(FindInvoice.call(id: @invoice.id))
          end
        end

        # A QUERY is one read. No envelope: finding nothing is an answer, not a failure.
        class FindInvoice < Query
          def initialize(id:)
            @id = typed(id, Integer)
          end

          def call
            Invoice.new(**InvoiceRecord.find(@id).slice(:id, :total, :settled_on))
          end
        end

        # A SHAPE holds a shape and computes nothing. It travels; the record never does.
        class Invoice < Shape
          def initialize(id:, total:, settled_on:)
            @id = typed(id, Integer)
            @total = typed(total, Money)
            @settled_on = typed(settled_on, Date, allow_nil: true)
          end
        end

        # A WORKFLOW sequences commands and queries. It never branches, and it spans
        # several transactions — so every step is idempotent and every stop is a legal state.
        class CloseTheMonth < Workflow
          def call
            invoices = ListUnsettledInvoices.call
            invoices.each { |invoice| SettleInvoice.call(invoice: invoice, paid_on: @on) }
            success(invoices.length)
          end
        end

        # A RECORD is the table and nothing else. No rules, no callbacks, no decisions.
        class InvoiceRecord < ApplicationRecord
          belongs_to :customer_record
        end
        ```

        **The rules that fall out of it**, and which the measures below are counting
        departures from:

        - Request handling calls **one** operation and decides nothing.
        - A command is one write and one transaction; sequencing writes is a workflow's job.
        - A query is one read; a query calling a query is the shape an N+1 arrives in.
        - Nothing reaches the outside from inside a transaction.
        - A record holds no rules, so no concern can settle on it.
        - Every class inherits exactly one of these, so its kind — and therefore what it may
          reach — is knowable without reading it.
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
      groups = GROUPS.map { |title, prefix| [title, concentration.select { |path, _| in?(path, prefix) }.first(3)] }
                     .reject { |_title, worst| worst.empty? }
      return "" if groups.empty?

      lines = ["## Where to start", "", <<~TEXT.chomp, ""]
        Ranked by how many different kinds of finding a file carries, not how many findings —
        a thousand of one kind is one problem, and six kinds is six.

        **Compared within its own kind, deliberately.** Half the measures only look at
        controllers, so ranking every file on one list puts controllers at the top and keeps
        them there — which says more about the measures than about the code.
      TEXT

      (lines + groups.flat_map { |title, worst| group(title, worst) }).join("\n")
    end

    GROUPS = [
      ["Request handling", "app/controllers/"],
      ["Persistence", "app/models/"],
      ["Everywhere else", nil],
    ].freeze

    def in?(path, prefix)
      return !GROUPS.any? { |_title, other| other && path.start_with?(other) } if prefix.nil?

      path.start_with?(prefix)
    end

    def group(title, worst)
      ["### #{title}", ""] +
        worst.map { |path, measures| "- `#{path}` — #{measures.length} #{measures.length == 1 ? "kind" : "kinds"}: #{measures.join(", ").downcase}" } +
        [""]
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
