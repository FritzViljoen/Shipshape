# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `steps_named` answer `["X"]` reddens the sequences-nothing tests; making
# it answer `[]` reddens every empty-expectation test; making `operation?` answer true reddens the
# not-a-step test; making `hidden_steps` answer `[]` reddens the private-helper test; making
# `unreadable_receivers` answer `[]` reddens the variable-receiver test; dropping `call_later` from
class AggregationIsReadableTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::AggregationIsReadable

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "workflow" => ["app/workflows/**/*.rb"],
        "deed" => ["app/deeds/**/*.rb"],
        "question" => ["app/questions/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "Matrix" => {
        "workflow" => %w[deed question shape], "deed" => ["question"], "question" => [], "shape" => []
      },
    },
  }.freeze

  WORKFLOW = "app/workflows/settle_month.rb"

  NAMESPACED_LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "workflow" => ["app/workflows/**/*.rb"],
        "deed" => ["app/deeds/**/*.rb"],
      },
      "Matrix" => { "workflow" => ["deed"], "deed" => [] },
    },
  }.freeze

  NAMESPACED = {
    "app/deeds/billing/settle_invoice.rb" =>
      "module Billing\n  class SettleInvoice < Deed\n  end\nend\n",
  }.freeze

  # The kinds are decided by the superclass, so the steps need real bodies on disk. They
  # declare no permission of their own: the class name is the permission.
  TREE = {
    "app/deeds/settle_invoice.rb" => "class SettleInvoice < Deed\nend\n",
    "app/deeds/notify_customer.rb" => "class NotifyCustomer < Deed\nend\n",
    "app/questions/list_invoices.rb" => "class ListInvoices < Question\nend\n",
    "app/shapes/invoice.rb" => "class Invoice < Shape\nend\n",
  }.freeze

  def test_a_workflow_that_sequences_nothing_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          success(:done)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleMonth#call` names no operation to run"
  end

  def test_the_offence_carries_the_reason_and_the_shape
    message = check(<<~RUBY).first.message
      class SettleMonth < Workflow
        def call
          success(:done)
        end
      end
    RUBY

    assert_includes message, "WHY: A workflow is a sequence"
    assert_includes message, "INSTEAD:"
    assert_includes message, "SettleInvoice.call(actor: actor, invoice_id: @id)"
  end

  def test_a_call_that_names_its_steps_is_the_shape
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor)
          NotifyCustomer.call(actor: @actor)
        end
      end
    RUBY
  end

  def test_a_question_step_counts_as_well_as_a_deed
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          ListInvoices.call(actor: @actor)
        end
      end
    RUBY
  end

  def test_a_constant_that_is_not_an_operation_is_not_a_step
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          Invoice.new(number: "1")
        end
      end
    RUBY

    assert_equal 1, found.length,
      "A shape is not a step. Holding one needs no permission, so it aggregates nothing — and a workflow that only builds shapes is still a workflow that sequences nothing."
  end

  def test_a_step_reached_from_a_private_helper_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          sequence
        end

        private

        def sequence
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY

    # Two: `call` names nothing, and the step is somewhere the reading does not reach.
    assert_equal 2, found.length,
      "**The blind spot the base class has, held here rather than left to production.** `RubyVM::AbstractSyntaxTree.of` reads `call` and nothing else, so a step behind a helper is a permission never demanded."
    assert(found.any? { |offence| offence.message.include?("reached from somewhere the permissions are not read from") })
  end

  def test_one_visible_step_does_not_excuse_a_hidden_one
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor)
          finish
        end

        private

        def finish
          NotifyCustomer.call(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`NotifyCustomer` is reached from somewhere",
      "**The fail-open the old shape allowed through.** One visible step satisfied the cop, and the hidden one was demanded of nobody — so the workflow ran, committed step one, then refused at the step nothing had checked."
  end

  # Legal Ruby that no reader can resolve to a permission.
  def test_a_receiver_that_is_not_a_constant_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          step = SettleInvoice
          step.call(actor: @actor)
        end
      end
    RUBY

    assert(found.any? { |offence| offence.message.include?("receiver is not a constant") })
  end

  # A deferred step still runs, so its permission is still owed — and the base class reads it.
  def test_a_deferred_step_is_a_step
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call_later(actor: @actor)
        end
      end
    RUBY
  end

  def test_a_deferred_step_hidden_in_a_helper_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor)
          finish
        end

        private

        def finish
          NotifyCustomer.call_later(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  # `::SettleInvoice` is a `COLON3` node. The base class dropped it silently, so the cop has
  # to read it the same way or one of them is wrong about what the workflow owes.
  def test_a_step_with_leading_colons_is_a_step
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          ::SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  # A signup sequence runs before anyone is identified and implements the other method.
  def test_an_anonymous_workflow_names_its_steps_the_same_way
    assert_empty check(<<~RUBY)
      class SignUp < Workflow
        def anonymous_call
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  def test_a_helper_that_touches_no_operation_is_not_a_hidden_step
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor)
        end

        private

        def summary
          Invoice.new(number: "1")
        end
      end
    RUBY
  end

  # A deed naming no operation is an ordinary deed, so only a workflow is failed for
  # sequencing nothing.
  def test_a_deed_that_names_no_operation_is_not_an_offence
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/deeds/settle_invoice.rb", files: TREE, other_cops: LAYOUT)
      class SettleInvoice < Deed
        def call
          success(:settled)
        end
      end
    RUBY
  end

  def test_a_deed_reaching_a_question_from_a_helper_is_an_offence
    found = offences(<<~RUBY, cop_class: COP, path: "app/deeds/settle_invoice.rb", files: TREE, other_cops: LAYOUT)
      class SettleInvoice < Deed
        def call
          success(load)
        end

        private

        def load
          ListInvoices.call(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`ListInvoices` is reached from somewhere",
      "**The widening.** Scoped to workflows, this was unreported — and it is the same fail-open one kind down: the deed demands nothing for a question it performs."
  end

  def test_a_deed_naming_its_question_in_call_is_the_shape
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/deeds/settle_invoice.rb", files: TREE, other_cops: LAYOUT)
      class SettleInvoice < Deed
        def call
          ListInvoices.call(actor: @actor)
        end
      end
    RUBY
  end

  # A part nested inside the workflow is reached only through it, so it is not a second
  # workflow to be judged on its own `call`.
  def test_a_nested_part_is_not_a_second_workflow
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        class Outcome
          def call
            success(:built)
          end
        end

        def call
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  def test_a_nested_classs_call_does_not_satisfy_the_workflow
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        class Report
          def call
            SettleInvoice.call(actor: @actor)
          end
        end

        def call
          success(:done)
        end
      end
    RUBY

    assert_equal 1, found.length,
      "A `call` on a NESTED class must not satisfy the outer workflow, which would then run with no steps and refuse nobody — green over the defect the cop exists for."
  end

  # `Billing::SettleInvoice` names one step, and the base class resolves it through the
  # workflow's own namespace. A cop that could not see it would fail correct code, and a cop
  # that fails correct code gets disabled.
  def test_a_namespaced_step_is_named
    assert_empty offences(<<~RUBY, cop_class: COP, path: WORKFLOW, files: NAMESPACED, other_cops: NAMESPACED_LAYOUT)
      class SettleMonth < Workflow
        def call
          Billing::SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: WORKFLOW, files: TREE, other_cops: LAYOUT)
  end
end
