# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `decisions_in` answer `[]` reddens every offence test; making it flag
# every send reddens the four tests that accept an outcome check, which are the ones that matter: a
# workflow must still be able to sequence. **`Shipshape/NoDecisionsInRequestHandling` cannot reach
# this**, and that was measured before this cop was written: with `workflow` added to its `Kinds`,
class WorkflowsBranchOnOutcomeTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::WorkflowsBranchOnOutcome

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "workflow" => ["app/workflows/**/*.rb"],
        "deed" => ["app/deeds/**/*.rb"],
      },
      "BaseClasses" => { "workflow" => ["Workflow"], "deed" => ["Deed"] },
      "Matrix" => { "workflow" => ["deed"], "deed" => [] },
    },
  }.freeze

  WORKFLOW = "app/workflows/settle_month.rb"

  def test_branching_on_what_a_step_answered_is_refused
    found = check("if charge.value.total > 100\n      success(1)\n    end")

    assert_equal 1, found.length
    assert_includes found.first.message, "is what a step answered with"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("if charge.value.settled?\n      success(1)\n    end").first.message

    assert_includes message, "WHY: A workflow is closer to a controller than to a deed"
    assert_includes message, "INSTEAD:"
    assert_includes message, "return failure(charge.error) if charge.failure?"
  end

  def test_a_case_over_what_a_step_answered_is_refused
    assert_equal 1, check("case charge.value.tier\n    when :gold then success(1)\n    end").length
  end

  def test_comparing_the_value_itself_is_still_deciding
    assert_equal 1, check("if charge.value > 100\n      success(1)\n    end").length
  end

  # **A workflow must still be able to sequence**, which is the half that matters.
  def test_the_outcome_is_what_a_workflow_may_ask
    assert_empty check("if charge.success?\n      success(1)\n    end")
    assert_empty check("if charge.failure?\n      failure(:no)\n    end")
    assert_empty check("if charge.error == :declined\n      failure(:declined)\n    end")
  end

  def test_using_the_value_outside_a_condition_is_the_point
    assert_empty check("Notify.call(actor: @actor, id: charge.value)\n    success(1)")
  end

  def test_a_deed_is_not_this_cops_business
    assert_empty offences("class CreatePerson < Deed\n  def call\n    if x.value.total > 1\n      1\n    end\n  end\nend\n",
                          cop_class: COP, path: "app/deeds/create_person.rb", other_cops: LAYOUT)
  end

  private

  def check(body)
    offences("class SettleMonth < Workflow\n  def call\n    charge = ChargeCard.call\n    #{body}\n  end\nend\n",
             cop_class: COP, path: WORKFLOW, other_cops: LAYOUT)
  end
end
