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

        private

        def stamp; end
      end
    RUBY
    "app/models/basket.rb" => <<~RUBY,
      class Basket
        def add; end

        def remove; end
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

  def test_it_finds_a_class_that_inherits_from_nothing
    assert_equal ["Basket"], labels("Classes that inherit from nothing")
  end

  def test_it_finds_classes_doing_several_things
    found = labels("Classes doing several things")

    # Three, not two: this measure counts public surface, and `to_param` is surface. The
    # persistence measure asks a different question — which of them are business rules —
    # and answers two. Different questions, different numbers, on purpose.
    assert_includes found.join, "Order — 3 public methods"
    assert_includes found.join, "Basket — 2 public methods"
  end

  # Controllers are excluded from that measure: a controller's actions are one job spelled
  # once per route, and counting them would drown the number that matters.
  def test_a_controller_is_not_counted_as_doing_several_things
    refute_includes labels("Classes doing several things").join, "OrdersController"
  end

  def test_it_finds_a_branch_in_an_action
    # Two now: the `if @order.paid?` and the guard clause added to prove chains rooted in
    # a constant are not counted as asking.
    assert_equal 2, row("Branches inside request handling").count
  end

  def test_it_finds_request_handling_reaching_persistence
    assert_equal ["Order.find"], labels("Request handling reaching straight into persistence")
  end

  # Declarations about the table are not behaviour, and private methods are not public.
  def test_it_finds_rules_on_persistence_and_not_declarations
    assert_equal ["#total", "#paid?"], labels("Rules living on persistence")
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

  def test_the_markdown_names_the_law_and_admits_what_it_truncates
    markdown = in_app { |root| Shipshape::ReportAsMarkdown.new(report: report_for(root), examples: 1).call }

    assert_includes markdown, "`no-lifecycle-callbacks`"
    assert_includes markdown, "…and 1 more"
    assert_includes markdown, "**What this cannot see:**"
  end

  private

  def row(title)
    in_app { |root| report_for(root)[:rows].find { |candidate| candidate.title == title } }
  end

  def labels(title)
    row(title).findings.map(&:label)
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
