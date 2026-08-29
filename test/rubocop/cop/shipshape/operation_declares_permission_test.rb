# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `declares_permission?` answer true reddens the undeclared tests.
# - Making `nested_in_a_class?` answer false reddens the nested-part test.
# - Making `one_of?` answer true unconditionally reddens the workflow and shape tests.
# - Hard-coding `constant_name` reddens the configurable-name test.
class OperationDeclaresPermissionTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OperationDeclaresPermission

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "query" => ["app/queries/**/*.rb"],
        "workflow" => ["app/workflows/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "Matrix" => {
        "workflow" => %w[command query], "command" => ["query"], "query" => [], "shape" => []
      },
    },
  }.freeze

  COMMAND = "app/commands/settle_invoice.rb"

  def test_a_command_with_no_permission_is_an_offence
    found = check(<<~RUBY)
      class SettleInvoice < Command
        def call
          success(InvoiceRecord.find(@invoice_id).settle!)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleInvoice` does not say who may run it"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class SettleInvoice < Command
        def call
          success(:done)
        end
      end
    RUBY

    assert_includes message, "WHY: Permission is a decision"
    assert_includes message, "INSTEAD:"
    assert_includes message, "return failure(:forbidden) unless @actor.may?(PERMISSION)"
    assert_includes message, "never `current_user`: ambient"
  end

  def test_a_declared_permission_is_the_shape
    assert_empty check(<<~RUBY)
      class SettleInvoice < Command
        PERMISSION = :settle_invoice

        def call
          return failure(:forbidden) unless @actor.may?(PERMISSION)

          success(:done)
        end
      end
    RUBY
  end

  def test_a_query_declares_one_too
    assert_equal 1, offences(<<~RUBY, cop_class: COP, path: "app/queries/list_invoices.rb", other_cops: LAYOUT).length
      class ListInvoices < Query
        def call
          success(InvoiceRecord.all)
        end
      end
    RUBY
  end

  # A workflow sequences operations that each declare their own; requiring one here would
  # state a fact twice.
  def test_a_workflow_is_outside_the_default_list
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/workflows/settle_month.rb", other_cops: LAYOUT)
      class SettleMonth < Workflow
        def call
          SettleInvoice.call(actor: @actor, invoice_id: 1)
        end
      end
    RUBY
  end

  def test_a_shape_declares_no_permission
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/shapes/invoice.rb", other_cops: LAYOUT)
      class Invoice < Shape
        def initialize(number:)
          @number = typed(number, String)
        end
      end
    RUBY
  end

  # A part nested inside its operation is reached only through the class that declared the
  # permission, so it is not a second operation.
  def test_a_nested_part_is_not_a_second_operation
    assert_empty check(<<~RUBY)
      class SettleInvoice < Command
        PERMISSION = :settle_invoice

        class Line
          def initialize(amount:)
            @amount = amount
          end
        end
      end
    RUBY
  end

  def test_the_constant_name_is_configurable
    found = offences(<<~RUBY, cop_class: COP, path: COMMAND, cop_config: { "ConstantName" => "ABILITY" }, other_cops: LAYOUT)
      class SettleInvoice < Command
        PERMISSION = :settle_invoice
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "ABILITY = :settle_invoice"
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, other_cops: LAYOUT)
  end
end
