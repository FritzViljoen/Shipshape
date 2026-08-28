# frozen_string_literal: true

require "test_helper"
require "shipshape/report"
require "shipshape/report_as_markdown"

# A small application holding one of each thing the report looks for, so every measure is
# asserted against code rather than trusted.
#
# Watched to fail: emptying any measure's `#call` reddens its own assertion and nothing
# else. The measures share `ClassReading` and are otherwise independent.
class ReportTest < Minitest::Test
  APP = {
    "app/controllers/orders_controller.rb" => <<~RUBY,
      class OrdersController < ApplicationController
        def show
          @basket = Basket.new
          @now = Time.now
          @today = Date.today
          @configured = Time.current
          @proper = Time.find_zone!("Africa/Johannesburg").now
          @invoiced_on = Date.new(2026, 1, 1)
          @order = Order.find(params[:id].to_i)
          return head :bad_request if Rails.env.development?

          if @order.paid?
            render :paid
          else
            render :unpaid
          end
        end
      end
    RUBY
    "app/models/order.rb" => <<~RUBY,
      class OrderNote
      end

      class Order < ApplicationRecord
        belongs_to :customer
        before_save :stamp
        after_commit :notify

        def total
          1
        end

        def paid?
          true
        end

        def to_param
          "x"
        end

        def settle!
          update!(paid: true)
        end

        private

        def stamp; end
      end
    RUBY
    "app/models/basket.rb" => <<~RUBY,
      class Basket
        def add; end

        def remove; end

        class Line
          def total; end
        end
      end
    RUBY
    "app/models/application_record.rb" => <<~RUBY,
      class ApplicationRecord
      end
    RUBY
    "app/models/paid_order.rb" => <<~RUBY,
      class PaidOrder < Order
      end
    RUBY
    "app/models/order_error.rb" => <<~RUBY,
      class OrderError < StandardError
      end

      class OrderMissingError < OrderError
      end
    RUBY
    "app/models/warehouse/bin.rb" => <<~RUBY,
      module Warehouse
        class Bin
          def label; end
        end
      end
    RUBY
    "db/schema.rb" => <<~RUBY,
      ActiveRecord::Schema[8.0].define(version: 1) do
        create_table "orders" do |t|
          t.string "reference", null: false
          t.string "note"
          t.integer "count", default: 0, null: false
          t.datetime "created_at", null: false
        end
      end
    RUBY
  }.freeze

  # No label: the path names the file, the source line shown beneath names the class, and a
  # third copy of the same word is the report stuttering at its reader.
  # A class nested inside another CLASS is that class's own business — an implementation
  # detail of the thing around it, which is the thing that needs a kind. Counting them put
  # five entries in the report for one file and stripped the namespace off every one.
  def test_a_class_owned_by_another_class_is_not_a_stray_object
    relatives = row("Classes that inherit from nothing").findings.map(&:relative)

    assert_equal 1, relatives.count("app/models/basket.rb")
  end

  # A class nested only in modules is namespaced, not owned — and its source line reads
  # `class Bin`, which says nothing about Warehouse. So the label carries the real name.
  def test_a_namespaced_class_is_named_in_full
    found = row("Classes that inherit from nothing").findings

    assert_includes found.map(&:label), "Warehouse::Bin"
    assert_includes found.map(&:label), ""
  end

  def test_it_finds_classes_doing_several_things
    found = row("Classes doing several things").findings

    # Four, not two, for Order: this measure counts public surface, and `to_param` is
    # surface. The persistence measure asks which of them are business rules and answers
    # differently. Different questions, different numbers, on purpose.
    assert_equal ["app/models/order.rb", "app/models/basket.rb"], found.map(&:relative)
    assert_equal ["4 public methods (worth a look)", "2 public methods"], found.map(&:label)
  end

  # Controllers are excluded from that measure: a controller's actions are one job spelled
  # once per route, and counting them would drown the number that matters.
  def test_a_controller_is_not_counted_as_doing_several_things
    refute_includes row("Classes doing several things").findings.map(&:relative).join, "controllers"
  end

  # One line per ACTION, not per branch: fifteen hundred branch locations is a list nobody
  # reads. The fixture has one action holding two branches.
  def test_it_reports_the_branchiest_actions_not_every_branch
    branches = row("Branches inside request handling")

    assert_equal 1, branches.count
    assert_equal ["#show — 2 branches"], branches.findings.map(&:label)
    assert_includes branches.headline, "2 branches in all"
  end

  def test_it_finds_request_handling_reaching_persistence
    assert_equal ["Order.find"], labels("Request handling reaching straight into persistence")
  end

  # Declarations about the table are not behaviour, and private methods are not public.
  def test_it_finds_rules_on_persistence_and_not_declarations
    assert_equal ["#total", "#paid?", "#settle!"], labels("Rules living on persistence")
  end

  def test_it_finds_lifecycle_callbacks
    assert_equal %w[before_save after_commit], labels("Lifecycle callbacks")
  end

  def test_it_finds_input_cast_where_it_is_used
    assert_equal ["to_i"], labels("Request input cast where it is used")
  end

  # Cohesion is the defining term, not size. A class whose methods share no state is
  # several classes wearing one name — and one that shares state is just long.
  def test_a_long_but_cohesive_class_is_not_a_god_class
    assert_empty labels("God classes")
  end

  def test_the_widest_tables_are_listed_in_order
    assert_equal ["orders — 4 columns"], labels("Widest tables")
  end

  # Timestamps are exempt; a column with a default is reported as a default rather than
  # counted twice.
  def test_it_reads_the_schema
    found = labels("Nullable columns and database defaults")

    assert_equal ["note — nullable", "count — has a default"], found
  end

  # A suggestion written in the reader's own nouns is one they can argue with; one written
  # in `YourCommand` and `SomeModel` is a slide.
  def test_it_proposes_a_shape_named_from_their_own_code
    proposal = row("Request handling reaching straight into persistence").proposal

    assert_includes proposal, "class FindOrder < Query"
    assert_includes proposal, "app/queries/find_order.rb"
    assert_includes proposal, "@id = typed(id, Integer)"
  end

  def test_a_proposal_with_no_inputs_has_no_empty_initializer
    proposal = row("Rules living on persistence").proposal

    assert_includes proposal, "class TotalOrder < Query"
    refute_includes proposal, "initialize()"
  end

  # A controller building a value object is the one thing a controller is entitled to do,
  # and counting it would inflate the number that matters most in this report.
  def test_a_value_object_in_app_models_is_not_persistence
    refute_includes labels("Request handling reaching straight into persistence").join, "Basket"
  end

  # `#find_user_from_rss_token` already says what it does. Appending the subject produced
  # `FindUserFromRssTokenUser`, a stutter that made the whole suggestion look generated.
  def test_an_action_outside_the_seven_keeps_its_own_name
    assert_equal "ArchiveOrder", Shipshape::Measures::Naming.operation_for(action: :archive_order, subject: "Order")
    assert_equal "ListOrders", Shipshape::Measures::Naming.operation_for(action: :index, subject: "Order")
  end

  # The message is better evidence than the action name: `User.where` is a read whatever
  # the method around it is called, and guessing Command from silence is how a report gets
  # laughed at.
  def test_the_message_decides_read_or_write_where_the_action_cannot
    assert_equal "Query", Shipshape::Measures::Naming.kind_for(:archive_order, message: :where)
    assert_equal "Command", Shipshape::Measures::Naming.kind_for(:index, message: :create!)
  end

  # Framework contract methods describe how the object is addressed, not what the business
  # does with it. `Category#to_param` was the first thing this report proposed extracting.
  def test_framework_methods_are_not_rules
    refute_includes labels("Rules living on persistence").join, "to_param"
  end

  # `if @order.paid?` — the caller taking a decision that belonged to the thing it asked.
  def test_it_finds_asking_then_branching
    assert_equal ["@order.paid?"], labels("Asking, then branching on the answer")
  end

  # THE ROOT OF THE CHAIN IS WHAT MATTERS. `Rails.env.development?` has a send as its
  # receiver, so checking only the immediate one let every configuration read through.
  def test_a_chain_rooted_in_a_constant_is_not_asking
    refute_includes labels("Asking, then branching on the answer").join, "Rails"
  end

  # Counting `Time`, `Rails` and a local constant made the worst action a list of
  # libraries rather than a sequence anybody would extract.
  def test_only_classes_this_repository_declares_count_as_orchestration
    found = labels("Actions orchestrating several classes")

    assert_equal 1, found.length
    assert_includes found.first, "Basket, Order"
    refute_includes found.first, "Time"
  end

  # A report with no denominator is an accusation. One that says four in five of your
  # actions are already dispatch is a measurement.
  def test_it_reports_the_share_that_is_already_right
    orchestration = row("Actions orchestrating several classes")

    assert_equal 1, orchestration.count
    assert_equal 1, orchestration.population
    assert_equal 0, orchestration.clean
  end

  # SUBTRACT UNITS, NOT FINDINGS. 186 sites across 45 controllers is not −141 clean
  # controllers, which is what this said before anybody looked at the arithmetic.
  def test_a_site_based_measure_counts_clean_units_not_clean_findings
    rules = row("Rules living on persistence")

    assert_operator rules.count, :>, rules.affected
    assert_operator rules.clean, :>=, 0
  end

  # Their own code, doing it right. Every codebase has some, and holding it up turns a
  # diagnostic from a verdict into a direction.
  def test_it_holds_up_their_own_clean_examples
    assert_includes row("Lifecycle callbacks").exemplars.map(&:relative), "app/models/basket.rb"
  end

  # The gem can see which it is, so it says so rather than handing the reader a judgement
  # it was perfectly able to make — and it names the write it found as the evidence.
  def test_it_infers_command_or_query_from_what_the_method_does
    proposals = row("Rules living on persistence").findings.map { |finding| finding.context }

    settle = proposals.find { |context| context[:method] == :settle! }
    total = proposals.find { |context| context[:method] == :total }

    assert settle[:writes]
    assert_equal :update!, settle[:write]
    refute total[:writes]
  end

  def test_the_proposal_names_the_evidence
    write = Shipshape::Measures::PersistenceWithBehaviour.new
    finding = write.call(sources_for_app).find { |candidate| candidate.context[:method] == :settle! }
    proposal = write.proposal([finding])

    assert_includes proposal, "class SettleOrder < Command"
    assert_includes proposal, "app/commands/settle_order.rb"
    assert_includes proposal, "It calls `update!`, so it writes: a Command."
  end

  # "98% of your classes are not god classes" reassures, and it is the wrong reading: one
  # is enough to slow a team down, so a denominator makes a concentrated harm look diffuse.
  # Many branches land in one action, so clean actions are actions without any — not
  # actions minus branches, which is not a number about anything.
  def test_branches_count_clean_actions_not_clean_branches
    branches = row("Branches inside request handling")

    assert_equal 1, branches.affected
    assert_equal 1, branches.population
    assert_equal 0, branches.clean
  end

  # The file-frequency sort was quietly undoing the branch-count sort underneath it, so the
  # worst action sat below the fold while a one-branch action from the same file showed.
  def test_a_measure_that_ranks_itself_is_not_re_sorted
    counts = row("Branches inside request handling").findings.map { |finding| finding.context[:branches] }

    assert_equal counts.sort.reverse, counts
  end

  # Findings arrive in directory order, so the first five examples were five lines from
  # whichever file sorts first alphabetically. That is a sample of the file system, not of
  # the problem.
  def test_examples_are_ranked_worst_first
    relatives = row("Rules living on persistence").findings.map(&:relative)

    assert_equal relatives.sort_by { |path| -relatives.count(path) }, relatives
  end

  # A bare count says nothing about scale. Two measures decline a denominator on purpose —
  # god classes, because one is enough to hurt, and widest tables, because a threshold there
  # would be invented — and both have to SAY so in text that always renders.
  def test_every_row_reports_a_share_or_states_why_it_will_not
    silent = report_rows.reject { |candidate| candidate.share || candidate.caveat }

    assert_empty silent.map(&:title), "a bare count with no denominator says nothing about scale"
  end

  # An abbreviation asks every reader to have been in the room where it was learned. The
  # published names stay in the source, where somebody is checking it against the paper.
  # An earlier version matched the node's SOURCE TEXT for the word `params`, so every
  # expression enclosing a parameter read counted as another read. The denominator came out
  # at 8,311 on an application with a few hundred, and the share it produced was meaningless.
  def test_a_parameter_read_is_counted_once_however_deeply_it_is_nested
    parsing = row("Request input cast where it is used")

    assert_equal 1, parsing.population
    assert_equal 1, parsing.count
  end

  # A FINDING NEVER RENDERS AS A BARE PATH, and that one rule decides both ways.
  #
  # Where the label carries the point — "4 public methods" — the class line repeats what
  # the path already said, so it is left out. Where there is no label, the line is all the
  # reader has: `offered_services_presenter.rb:70` says nothing about which of the three
  # classes in that file is meant.
  def test_a_finding_never_renders_as_a_bare_path
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }

    assert_includes text, "`before_save :stamp`"
    assert_includes text, "`if @order.paid?`"
    assert_includes text, "`class Basket`"
    refute_includes text, "`class Order < ApplicationRecord`"
  end

  # The reference and its code sit on two lines, so the invariant is about the pair: a
  # bullet carrying nothing but a path must be followed by the line it points at.
  def test_every_example_says_something_the_path_does_not
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }
    lines = text.lines.map(&:rstrip)

    bare = lines.each_with_index.select do |line, index|
      line.match?(/\A- `[^`]+:\d+`\z/) && !lines[index + 1].to_s.match?(/\A  `.+`\z/)
    end

    assert_empty bare.map(&:first), "a path and a line number on their own tell the reader nothing"
  end

  # `Paid@order.call(@order: @order)` is what came out before anybody read the generated
  # line. The sigil is Ruby punctuation; the word under it is the subject.
  def test_a_proposal_strips_the_sigil_from_an_instance_variable
    proposal = row("Asking, then branching on the answer").proposal

    assert_includes proposal, "PaidOrder.call(order: @order)"
    refute_includes proposal, "Paid@order"
  end

  # Twelve lists tell a reader who knows the codebase what they knew. What they cannot see
  # by reading down the page is that one file appears in eight of the twelve.
  # A file name is the first index anybody has. Three classes in one file means two cannot
  # be found by the name they are used under.
  def test_it_finds_a_file_declaring_several_classes
    found = row("Files declaring several classes").findings

    assert_equal ["app/models/order.rb", "app/models/order_error.rb"], found.map(&:relative)
    assert_includes found.first.label, "2 classes"
  end

  # Twelve lists of findings with no argument around them is a tool showing off. The reader
  # needs the claim before the counts, or every number reads as a complaint about a decision
  # somebody made for a good reason in 2016.
  def test_it_makes_the_argument_before_the_counts
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }

    assert_operator text.index("## What this is measuring"), :<, text.index("| What | Found")
    assert_includes text, "Nothing here is a bug."
  end

  # A report that only says what is wrong leaves the reader to invent the alternative, and
  # they will invent the one they already know.
  def test_it_shows_the_shape_it_is_asking_for
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }

    assert_includes text, "## What the shape is"
    assert_includes text, "class SettleInvoice < Command"
    assert_includes text, "class CloseTheMonth < Workflow"
    assert_operator text.index("## What the shape is"), :<, text.index("## Classes that inherit")
  end

  # A BASE CLASS IS NOT A STRAY OBJECT. `ApplicationRecord` inherits from nothing on
  # purpose, and it is the answer to that measure rather than an instance of it. Derived
  # from the code — a class is a base if something else here inherits from it.
  def test_a_base_class_is_not_counted_as_inheriting_from_nothing
    relatives = row("Classes that inherit from nothing").findings.map(&:relative)

    refute_includes relatives, "app/models/application_record.rb"
    assert_includes relatives, "app/models/basket.rb"
  end

  # Ruby has single inheritance, so "more than one" means depth: a chain of three, where
  # the middle class is a place somebody keeps things.
  def test_it_finds_inheritance_deeper_than_one_level
    found = row("Inheritance deeper than one level").findings

    assert_equal ["PaidOrder < Order < ApplicationRecord"], found.map(&:label)
  end

  # An error taxonomy has no behaviour to accrete, and Ruby requires the depth. Counting
  # them buried the finding — nine hundred, of which most were one error file.
  def test_an_error_hierarchy_is_not_accreted_behaviour
    assert_empty row("Inheritance deeper than one level").findings.map(&:label).grep(/Error/)
  end

  # A point in time carries its zone; a calendar date does not.
  def test_it_finds_moments_built_without_a_zone
    labels = row("Times built without naming a zone").findings.map(&:label)

    assert_includes labels.join, "Time.now — takes whatever offset the process has"
    assert_includes labels.join, "Date.today"
  end

  # Unzoned first: `Time.now` produces a booking an hour out, `Time.current` produces one
  # zone for an application serving two countries. Different sizes of the same mistake.
  def test_the_worse_tier_is_listed_first
    labels = row("Times built without naming a zone").findings.map(&:label)

    assert_operator labels.index { |label| label.start_with?("Time.now") },
                    :<,
                    labels.index { |label| label.start_with?("Time.current") }
  end

  # A calendar date carries no zone on purpose — converting one moves it a day.
  def test_a_calendar_date_is_not_a_moment
    assert_empty row("Times built without naming a zone").findings.map(&:label).grep(/Date\.new/)
  end

  def test_a_named_zone_is_held_up_as_already_right
    assert_includes row("Times built without naming a zone").exemplars.map(&:label).join, "find_zone!"
  end

  def test_it_says_where_to_start
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }

    assert_includes text, "## Where to start"
    assert_match(%r{- `app/models/order\.rb` — \d+ kinds:}, text)
  end

  # Ranked by breadth, not volume: a thousand findings of one kind is one problem, and six
  # kinds is six.
  def test_where_to_start_ranks_by_how_many_measures_not_how_many_findings
    persistence = section_of("Persistence").scan(/- `([^`]+)` — (\d+) kind/)
    counts = persistence.map { |_path, count| count.to_i }

    assert_equal counts.sort.reverse, counts
  end

  # Half the measures only look at controllers, so one list ranks every controller above
  # every model — which says more about the measures than about the code. `booking.rb` at
  # 186 methods and 113 columns did not appear on that list at all.
  def test_files_are_compared_within_their_own_kind
    assert_includes section_of("Request handling"), "app/controllers/orders_controller.rb"
    assert_includes section_of("Persistence"), "app/models/order.rb"
    refute_includes section_of("Persistence"), "controllers"
  end

  def test_no_abbreviations_reach_the_reader
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }

    %w[WMC TCC ATFD].each { |jargon| refute_includes text, jargon }
  end

  def test_god_classes_report_no_ratio
    assert_nil row("God classes").population
  end

  def test_the_markdown_names_the_law_and_admits_what_it_truncates
    markdown = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root), examples: 1).call }

    assert_includes markdown, "`no-lifecycle-callbacks`"
    assert_includes markdown, "…and 1 more"
    assert_includes markdown, "**What this cannot see:**"
  end

  private

  def section_of(title)
    text = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root)).call }

    text[/### #{title}\n(.*?)\n\n/m].to_s
  end

  def report_rows
    in_app { |root| report_for(root)[:rows] }
  end

  def row(title)
    in_app { |root| report_for(root)[:rows].find { |candidate| candidate.title == title } }
  end

  def labels(title)
    row(title).findings.map(&:label)
  end

  # The measure under test, given the fixture's sources directly.
  def sources_for_app
    in_app { |root| Shipshape::Sources.new(root: root).call }
  end

  def report_for(root)
    Shipshape::Report.new(root: root).call
  end

  def in_app
    Dir.mktmpdir("shipshape-report") do |root|
      APP.each do |path, contents|
        target = File.join(root, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, contents)
      end

      yield(root)
    end
  end
end
