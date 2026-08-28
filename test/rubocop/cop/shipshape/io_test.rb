# frozen_string_literal: true

require "test_helper"

# Reading and changing state outside this process. Same two operations as the internal pair,
# marked, and sisters of it — so a command may not do IO.
#
# The reason is the transaction, and it is the only reason that matters: a command is exactly
# one transaction, and an external call inside one holds a database transaction open across a
# network round trip.
#
# Watched to fail, and it reddened ONE test rather than all of them: the matrix rows already
# exclude these pairs, so the sister rule is belt-and-braces here rather than the only guard.
# Said plainly because the opposite claim would have been the easy one to write.
#
# It still earns its place: the matrix is configuration and can be edited, while the sister
# rule cannot — a row naming a sister stops the run.
class IoTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "workflow" => ["app/workflows/**/*.rb"],
      "command" => ["app/commands/**/*.rb"],
      "query" => ["app/queries/**/*.rb"],
      "io_query" => ["app/io/**/*.rb"],
      "io_command" => ["app/io/**/*.rb"],
      "shape" => ["app/shapes/**/*.rb"],
      "record" => ["app/records/**/*_record.rb"],
    },
    "BaseClasses" => {
      "workflow" => ["Workflow"],
      "command" => ["Command"],
      "query" => ["Query"],
      "io_query" => ["IoQuery"],
      "io_command" => ["IoCommand"],
      "shape" => ["Shape"],
      "record" => ["ApplicationRecord"],
    },
    "Sisters" => [%w[command io_command], %w[query io_query]],
    "Matrix" => {
      "workflow" => %w[command query io_command io_query shape],
      "command" => %w[query shape record],
      "query" => %w[shape record],
      "io_command" => %w[query shape],
      "io_query" => ["shape"],
      "shape" => [],
      "record" => [],
    },
  }.freeze

  TREE = {
    "app/workflows/settle_month.rb" => "class SettleMonth < Workflow\nend\n",
    "app/commands/charge_account.rb" => "class ChargeAccount < Command\nend\n",
    "app/queries/list_people.rb" => "class ListPeople < Query\nend\n",
    "app/io/io_send_invoice.rb" => "class IoSendInvoice < IoCommand\nend\n",
    "app/io/io_fetch_rates.rb" => "class IoFetchRates < IoQuery\nend\n",
    "app/shapes/money.rb" => "class Money < Shape\nend\n",
    "app/records/invoice_record.rb" => "class InvoiceRecord < ApplicationRecord\nend\n",
  }.freeze

  # The rule this whole split exists for.
  def test_a_command_may_not_write_to_the_outside
    found = check(<<~RUBY, "app/commands/charge_account.rb")
      class ChargeAccount < Command
        def call
          IoSendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A command may not call an io_command"
    assert_includes found.first.message, "They are sisters"
  end

  # And not read from it either: the transaction is held open just the same by a read.
  def test_a_command_may_not_read_from_the_outside
    found = check(<<~RUBY, "app/commands/charge_account.rb")
      class ChargeAccount < Command
        def call
          IoFetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A command may not call an io_query"
  end

  def test_a_query_may_not_read_from_the_outside
    found = check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople < Query
        def call
          IoFetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call an io_query"
  end

  # A workflow is the only kind that has accepted the bill for spanning them.
  def test_a_workflow_sequences_the_external_call_and_the_local_write
    assert_empty check(<<~RUBY, "app/workflows/settle_month.rb")
      class SettleMonth < Workflow
        def call
          IoFetchRates.call
          ChargeAccount.call
          IoSendInvoice.call
        end
      end
    RUBY
  end

  # Two kinds, one tree, told apart by what they inherit — the same mechanism as the legacy
  # doors, so the `Io` prefix marks the call site and the base class carries the shape.
  def test_the_two_io_kinds_are_told_apart_by_their_base_class
    found = check(<<~RUBY, "app/io/io_fetch_rates.rb")
      class IoFetchRates < IoQuery
        def call
          IoSendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_query may not call an io_command"
  end

  # It touches no record: the external call and the write recording its result are two
  # steps, so a failed remote call leaves no half-written row behind.
  def test_an_io_command_may_not_write_to_the_local_store
    found = check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoCommand
        def call
          InvoiceRecord.create!
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_command may not call a record"
  end

  def test_an_io_operation_may_build_shapes
    assert_empty check(<<~RUBY, "app/io/io_fetch_rates.rb")
      class IoFetchRates < IoQuery
        def call
          [Money.new(cents: 1)]
        end
      end
    RUBY
  end

  private

  def check(source, path)
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE)
  end
end
