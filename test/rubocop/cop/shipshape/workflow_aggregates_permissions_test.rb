# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `derived_permissions` answer `[]` reddens the missing-entry test.
# - Making `declared_permissions` answer the derived set reddens both mismatch tests.
# - Making `operation?` answer true reddens the not-a-step test.
# - Making `on_class` skip the nil check reddens the undeclared test.
# - Removing the nested-class guard reddens the nested-part test.
class WorkflowAggregatesPermissionsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::WorkflowAggregatesPermissions

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "workflow" => ["app/workflows/**/*.rb"],
        "command" => ["app/commands/**/*.rb"],
        "query" => ["app/queries/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "Matrix" => {
        "workflow" => %w[command query shape], "command" => ["query"], "query" => [], "shape" => []
      },
    },
  }.freeze

  WORKFLOW = "app/workflows/settle_month.rb"

  # The kinds are decided by the superclass, so the steps need real bodies on disk.
  TREE = {
    "app/commands/settle_invoice.rb" => "class SettleInvoice < Command\n  PERMISSION = :settle_invoice\nend\n",
    "app/commands/notify_customer.rb" => "class NotifyCustomer < Command\n  PERMISSION = :notify_customer\nend\n",
    "app/queries/list_invoices.rb" => "class ListInvoices < Query\n  PERMISSION = :list_invoices\nend\n",
    "app/shapes/invoice.rb" => "class Invoice < Shape\nend\n",
  }.freeze

  def test_a_workflow_with_no_permissions_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleMonth` is a workflow and does not name the permissions"
  end

  def test_the_offence_carries_the_reason_and_an_example_naming_the_real_steps
    message = check(<<~RUBY).first.message
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor)
          NotifyCustomer.call(actor: @actor)
        end
      end
    RUBY

    assert_includes message, "WHY: A workflow spans several transactions"
    assert_includes message, "INSTEAD:"
    assert_includes message, "PERMISSIONS = [SettleInvoice::PERMISSION, NotifyCustomer::PERMISSION].freeze"
    assert_includes message, "return failure(:forbidden) unless @actor.may_all?(PERMISSIONS)"
  end

  def test_a_matching_declaration_is_the_shape
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        PERMISSIONS = [SettleInvoice::PERMISSION, NotifyCustomer::PERMISSION].freeze

        def call
          return failure(:forbidden) unless @actor.may_all?(PERMISSIONS)

          SettleInvoice.call(actor: @actor)
          NotifyCustomer.call(actor: @actor)
        end
      end
    RUBY
  end

  # The rot this law exists for: a step is added and the list is not.
  def test_a_step_the_list_does_not_name_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        PERMISSIONS = [SettleInvoice::PERMISSION].freeze

        def call
          SettleInvoice.call(actor: @actor)
          NotifyCustomer.call(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "missing `NotifyCustomer`"
  end

  # The other direction is a different mistake, and says so.
  def test_a_permission_for_a_step_it_does_not_call_is_an_offence
    found = check(<<~RUBY)
      class SettleMonth < Workflow
        PERMISSIONS = [SettleInvoice::PERMISSION, ListInvoices::PERMISSION].freeze

        def call
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "names `ListInvoices`, which it does not call"
  end

  def test_a_query_step_counts_as_well_as_a_command
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        PERMISSIONS = [ListInvoices::PERMISSION, SettleInvoice::PERMISSION].freeze

        def call
          ListInvoices.call(actor: @actor)
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  # A shape is not a step, so holding one needs no permission.
  def test_a_constant_that_is_not_an_operation_is_not_a_step
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        PERMISSIONS = [SettleInvoice::PERMISSION].freeze

        def call
          Invoice.new(number: "1")
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  def test_a_command_is_not_a_workflow
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/commands/settle_invoice.rb", files: TREE, other_cops: LAYOUT)
      class SettleInvoice < Command
        PERMISSION = :settle_invoice

        def call
          ListInvoices.call(actor: @actor)
        end
      end
    RUBY
  end

  # A part nested inside the workflow is reached only through it, so it declares nothing.
  def test_a_nested_part_is_not_a_second_workflow
    assert_empty check(<<~RUBY)
      class SettleMonth < Workflow
        PERMISSIONS = [SettleInvoice::PERMISSION].freeze

        class Outcome
          def initialize(settled:)
            @settled = settled
          end
        end

        def call
          SettleInvoice.call(actor: @actor)
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: WORKFLOW, files: TREE, other_cops: LAYOUT)
  end
end
