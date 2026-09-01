# frozen_string_literal: true

require "test_helper"

# Watched to fail, each one run: emptying `RUNS` reddens all seven offence tests, and so does
# returning `[]` from `nested` — the clean tests stay green, which is exactly the shape a
# silent cop has. Dropping `call_later` from `RUNS` reddens the deferred test, and replacing
# the `const_type?` half of `operation_call?` with a bare receiver check reddens the local
# test, which is the one that says a lambda held in a local is not an operation.
class NoNestedOperationCallsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoNestedOperationCalls

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "workflow" => ["app/workflows/**/*.rb"],
        "view_component" => ["app/view_components/**/*.rb"],
      },
      "Matrix" => { "request_handling" => ["workflow"], "workflow" => [], "view_component" => [] },
      "BaseClasses" => { "workflow" => ["Workflow"], "view_component" => ["ApplicationViewComponent"] },
    },
  }.freeze

  CONTROLLER = "app/controllers/orders_controller.rb"

  def test_an_operation_call_inside_another_is_an_offence
    found = check("CreateOrder.call(composition: FindOrderComposition.call(cart_id: 1))")

    assert_equal 1, found.length
    assert_includes found.first.message, "`FindOrderComposition.call` is an argument to another"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("CreateOrder.call(composition: FindOrderComposition.call(cart_id: 1))").first.message

    assert_includes message, "WHY: Two operations run in one statement"
    assert_includes message, "INSTEAD:"
    assert_includes message, "composition = FindOrderComposition.call(cart_id: cart_id)"
  end

  def test_the_inner_call_is_what_is_reported
    found = check("CreateOrder.call(composition: FindOrderComposition.call(cart_id: 1))")

    assert_equal "FindOrderComposition.call(cart_id: 1)", found.first.location.source
  end

  # Depth is not the test: one level is already the defect, and each inner call is named once.
  def test_a_three_deep_chain_names_each_inner_call_once
    found = check("A.call(x: B.call(y: C.call))")

    assert_equal 2, found.length
    assert_equal %w[B.call(y:\ C.call) C.call], found.map { |offence| offence.location.source }.sort
  end

  def test_a_call_nested_deeper_in_an_argument_is_still_nested
    found = check("CreateOrder.call(lines: FindLines.call(cart_id: 1).map(&:id))")

    assert_equal 1, found.length
  end

  def test_a_deferred_call_is_a_call
    assert_equal 1, check("SettleInvoice.call_later(total: FindTotal.call(id: 1))").length
  end

  def test_two_statements_are_what_the_rule_asks_for
    assert_empty check(<<~RUBY.chomp)
      composition = FindOrderComposition.call(cart_id: 1)
      CreateOrder.call(composition: composition)
    RUBY
  end

  def test_an_ordinary_argument_is_not_a_call
    assert_empty check("CreateOrder.call(cart_id: params[:cart_id], actor: current_user)")
  end

  # A block or a lambda reached through a local is not an operation, and never was one.
  def test_a_local_holding_something_callable_is_not_an_operation
    assert_empty check("CreateOrder.call(composition: builder.call(cart_id: 1))")
  end

  def test_an_operation_called_from_a_render_argument_is_out_of_scope
    assert_empty check("render json: FindOrder.call(id: 1)")
  end

  def test_a_workflow_sequencing_two_steps_is_governed
    found = offences(<<~RUBY, cop_class: COP, path: "app/workflows/settle_month.rb", other_cops: LAYOUT)
      class SettleMonth < Workflow
        def call
          NotifyCustomer.call(invoice: FindInvoice.call(id: @id))
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  # Its whole row is `shape`, so a call from one is CallGraph's offence rather than this one's.
  def test_a_view_component_is_left_to_the_call_graph
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/view_components/order_component.rb", other_cops: LAYOUT)
      class OrderComponent < ApplicationViewComponent
        def call
          CreateOrder.call(composition: FindOrderComposition.call(cart_id: 1))
        end
      end
    RUBY
  end

  private

  def check(body)
    offences(<<~RUBY, cop_class: COP, path: CONTROLLER, other_cops: LAYOUT)
      class OrdersController
        def create
          #{body.gsub("\n", "\n    ")}
        end
      end
    RUBY
  end
end
