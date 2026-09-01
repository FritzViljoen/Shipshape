# frozen_string_literal: true

require "test_helper"

# Watched to fail, each one run: emptying `ARITHMETIC` reddens three tests and the message
# test; emptying `THRESHOLD` reddens the ordering test; emptying `TOTALS` reddens the total
# test. Making `literal?` answer `false` reddens the offset and duration tests, and making
# `collection?` answer `false` reddens the composition test — the two guards that keep
# `index + 1` and `first.to_a + second.to_a` out of the report. Adding `count` to `TOTALS`
# reddens the cardinality test, which is what holds cardinality apart from totalling.
class OnlyOperationsCalculateTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OnlyOperationsCalculate

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "view_component" => ["app/view_components/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "query" => ["app/queries/**/*.rb"],
      },
      "Matrix" => { "view_component" => [], "request_handling" => ["query"], "query" => [] },
      "BaseClasses" => { "view_component" => ["ApplicationViewComponent"], "query" => ["Query"] },
    },
  }.freeze

  COMPONENT = "app/view_components/invoice_component.rb"

  def test_arithmetic_between_two_reads_is_a_calculation
    found = check("@adults + @children")

    assert_equal 1, found.length
    assert_includes found.first.message, "`@adults + @children` works out a new value here"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("@invoice.total - @invoice.paid").first.message

    assert_includes message, "WHY: A derivation is a rule"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class ListInvoiceLines < Query"
  end

  def test_an_ordering_comparison_between_two_reads_answers_a_domain_question
    found = check("@ends_at < @now")

    assert_equal 1, found.length
    assert_includes found.first.message, "answers a domain question here"
  end

  def test_totalling_a_collection_is_an_operations_answer
    found = check("@lines.map(&:amount).sum")

    assert_equal 1, found.length
    assert_includes found.first.message, "`sum` totals a collection here"
  end

  def test_every_arithmetic_operator_is_caught
    %w[+ - * / %].each do |operator|
      assert_equal 1, check("@charged #{operator} @rate").length, operator
    end
  end

  # A literal on either side is an offset the author wrote down, not a rule the domain owns.
  def test_an_offset_against_a_literal_is_placement
    assert_empty check("@index + 1")
    assert_empty check("@count > 0")
  end

  def test_a_duration_is_a_number_wearing_a_method
    assert_empty check("@shown_at - 30.days")
  end

  def test_identity_is_not_a_threshold
    assert_empty check("@row.id == @selected_id")
  end

  def test_cardinality_is_a_fact_about_the_collection
    assert_empty check("@lines.count")
  end

  # Assembling a list answers no question an operation could have answered instead.
  def test_composing_collections_is_not_calculating
    assert_empty check("@first.to_a + @second.to_a")
  end

  def test_an_operation_is_where_calculation_lives
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/queries/list_invoice_lines.rb", other_cops: LAYOUT)
      class ListInvoiceLines < Query
        def call
          @units * @rate
        end
      end
    RUBY
  end

  def test_request_handling_is_governed_too
    found = offences(<<~RUBY, cop_class: COP, path: "app/controllers/invoices_controller.rb", other_cops: LAYOUT)
      class InvoicesController < ApplicationController
        def show
          @due = @invoice.total - @invoice.paid
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  private

  def check(expression)
    offences(<<~RUBY, cop_class: COP, path: COMPONENT, other_cops: LAYOUT)
      class InvoiceComponent < ApplicationViewComponent
        def call
          #{expression}
        end
      end
    RUBY
  end
end
