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
          @order = Order.find(params[:id].to_i)
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

    assert_includes found.join, "Order — 2 public methods"
    assert_includes found.join, "Basket — 2 public methods"
  end

  # Controllers are excluded from that measure: a controller's actions are one job spelled
  # once per route, and counting them would drown the number that matters.
  def test_a_controller_is_not_counted_as_doing_several_things
    refute_includes labels("Classes doing several things").join, "OrdersController"
  end

  def test_it_finds_a_branch_in_an_action
    assert_equal 1, row("Branches inside request handling").count
  end

  def test_it_finds_request_handling_reaching_persistence
    assert_equal ["Order"], labels("Request handling reaching straight into persistence")
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

  # Timestamps are exempt; a column with a default is reported as a default rather than
  # counted twice.
  def test_it_reads_the_schema
    found = labels("Nullable columns and database defaults")

    assert_equal ["note — nullable", "count — has a default"], found
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
