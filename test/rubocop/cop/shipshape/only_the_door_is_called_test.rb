# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `operation?` answer true reddens the not-an-operation test; emptying
# `allowed` reddens the door test and the introspection test; making `refers_to_itself?` answer
# false reddens the self-reference test. This is the check that does not rely on `private`.
# Everything else guarding the door is a convention Ruby steps over: `private` is not a wall,
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

  DEFERRABLE = { "DeferrableKinds" => %w[command], "DeferredMessages" => %w[call_later] }.freeze

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

  # The name, which a label table and a seed are keyed by.
  def test_the_class_level_name_is_allowed
    assert_empty check("b = SettleInvoice.permission\n")
  end

  # **The predicate and its respelling are both refused.** `permits?` is private, and
  # `permissions` asks the same question in more words — and disagrees with the door for an
  # anonymous operation, so a view using it hides a button the door would open.
  def test_asking_whether_an_actor_may_is_refused_in_either_spelling
    assert_equal 1, check("c = SettleMonth.permits?(actor)\n").length
    assert_equal 1, check("d = SettleMonth.permissions.all? { |p| actor.may?(p) }\n").length
  end

  def test_a_workflow_may_not_defer_a_step
    found = offences(<<~RUBY, cop_class: COP, path: "app/workflows/settle_month.rb", files: TREE, other_cops: LAYOUT)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call_later(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "defers a step of a sequence",
      "**A sequence runs its steps, it does not post them.** Deferred, step three can start before step two has happened, and the workflow answers success for work that has not been done."
    assert_includes found.first.message, "answers success for work that has not been done"
  end

  # The same command deferred from a command is the ordinary shape, and stays allowed.
  def test_a_command_may_still_defer
    assert_empty check("SettleInvoice.call_later(actor: actor)\n")
  end

  def test_the_forwarder_is_refused_by_name
    assert_equal 1, check("SettleInvoice.__perform__(actor)").length,
      "It does not rely on visibility, so a bypass the other guards miss is still refused."
  end

  def test_allocate_is_not_the_door_either
    assert_equal 1, check("SettleInvoice.allocate").length,
      "The route `private_class_method :new` alone left open: `allocate` is public on every Ruby class and skips `initialize` entirely."
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

  def test_a_command_may_be_deferred
    assert_empty check("SettleInvoice.call_later(actor: actor, invoice_id: 1)"),
      "**Deferring is running, at a different time**, so the writing doors answer it."
  end

  def test_a_workflow_may_not_be_deferred
    found = check("SettleMonth.call_later(actor: actor)")

    assert_equal 1, found.length,
      "**Per kind, not one flat list.** `call_later` exists only on the writing doors, so allowing it everywhere let `SomeWorkflow.call_later(…)` pass this cop and fail at runtime with `NoMethodError` — the guard moving a failure from the build into production."
    assert_includes found.first.message, "is not the door"
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
             cop_class: COP, cop_config: DEFERRABLE, path: CONTROLLER, files: TREE,
             other_cops: LAYOUT)
  end
end
