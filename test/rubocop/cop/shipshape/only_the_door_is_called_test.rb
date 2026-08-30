# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `operation?` answer true reddens the not-an-operation test.
# - Emptying `allowed` reddens the door test and the introspection test.
# - Making `refers_to_itself?` answer false reddens the self-reference test.
#
# This is the check that does not rely on `private`. Everything else guarding the door is a
# convention Ruby steps over: `private` is not a wall, `send` undoes `private_class_method`,
# and a subclass can redeclare a private method public. This reads the call site instead.
class OnlyTheDoorIsCalledTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OnlyTheDoorIsCalled

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "workflow" => ["app/workflows/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "BaseClasses" => {
        "command" => ["Command"], "workflow" => ["Workflow"], "shape" => ["Shape"]
      },
      "Matrix" => {
        "request_handling" => %w[command workflow shape],
        "command" => ["shape"], "workflow" => ["command"], "shape" => []
      },
    },
  }.freeze

  TREE = {
    "app/commands/settle_invoice.rb" => "class SettleInvoice < Command\nend\n",
    "app/workflows/settle_month.rb" => "class SettleMonth < Workflow\nend\n",
    "app/shapes/invoice.rb" => "class Invoice < Shape\nend\n",
  }.freeze

  CONTROLLER = "app/controllers/invoices_controller.rb"

  def test_a_message_that_is_not_the_door_is_refused
    found = check("SettleInvoice.new(invoice_id: 1)")

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleInvoice.new` is not the door"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("SettleInvoice.build_from(params)").first.message

    assert_includes message, "WHY: The door is where the permission check runs"
    assert_includes message, "`private` is not a wall"
    assert_includes message, "INSTEAD:"
    assert_includes message, "SettleInvoice.call(actor: actor, invoice_id: 1)"
  end

  def test_the_door_is_the_door
    assert_empty check("SettleInvoice.call(actor: actor, invoice_id: 1)")
  end

  # Asking an operation what it needs, without running it — a view hiding a button it may
  # not offer, or the permission catalogue.
  def test_the_class_level_api_is_allowed
    assert_empty check(<<~RUBY)
      a = SettleMonth.permissions
      b = SettleInvoice.permission
      c = SettleMonth.permits?(actor)
      [a, b, c]
    RUBY
  end

  # It does not rely on visibility, so a bypass the other guards miss is still refused.
  def test_the_forwarder_is_refused_by_name
    assert_equal 1, check("SettleInvoice.__perform__(actor)").length
  end

  # The route `private_class_method :new` alone left open: `allocate` is public on every Ruby
  # class and skips `initialize` entirely.
  def test_allocate_is_not_the_door_either
    assert_equal 1, check("SettleInvoice.allocate").length
  end

  # A variable holding the class is the stated blind spot. `private_class_method :new,
  # :allocate` refuses this at runtime, and an operation declares no other public class
  # method, so there is nothing else to reach for.
  def test_an_operation_held_in_a_variable_is_the_stated_blind_spot
    assert_empty check("command = SettleInvoice\n    command.new(invoice_id: 1)")
  end

  def test_something_that_is_not_an_operation_is_left_alone
    assert_empty check("Invoice.new(number: '1')")
  end

  # A class naming itself is not a call site reaching in.
  def test_a_class_referring_to_itself_is_not_a_call_site
    assert_empty offences("class SettleInvoice < Command\n  def self.build\n    SettleInvoice.new\n  end\nend\n",
                          cop_class: COP, path: "app/commands/settle_invoice.rb",
                          files: TREE, other_cops: LAYOUT)
  end

  private

  def check(body)
    offences("class InvoicesController\n  def create\n    #{body}\n  end\nend\n",
             cop_class: COP, path: CONTROLLER, files: TREE, other_cops: LAYOUT)
  end
end
