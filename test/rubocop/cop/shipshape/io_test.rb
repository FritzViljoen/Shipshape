# frozen_string_literal: true

require "test_helper"

# Reading and changing state outside this process. Same two operations as the internal pair,
# marked, and sisters of it — so a write may not do IO.
class IoTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "workflow" => ["app/workflows/**/*.rb"],
      "write" => ["app/writes/**/*.rb"],
      "read" => ["app/reads/**/*.rb"],
      "io_read" => ["app/io/**/*.rb"],
      "io_write" => ["app/io/**/*.rb"],
      "shape" => ["app/shapes/**/*.rb"],
      "record" => ["app/records/**/*_record.rb"],
    },
    "BaseClasses" => {
      "workflow" => ["Workflow"],
      "write" => ["Write"],
      "read" => ["Read"],
      "io_read" => ["IoRead"],
      "io_write" => ["IoWrite"],
      "shape" => ["Shape"],
      "record" => ["ApplicationRecord"],
    },
    "Sisters" => [%w[write io_write], %w[read io_read]],
    "Matrix" => {
      "workflow" => %w[write read io_write io_read shape],
      "write" => %w[read shape record],
      "read" => %w[shape record],
      "io_write" => %w[io_read shape],
      "io_read" => ["shape"],
      "shape" => [],
      "record" => [],
    },
  }.freeze

  TREE = {
    "app/workflows/settle_month.rb" => "class SettleMonth < Workflow\nend\n",
    "app/writes/charge_account.rb" => "class ChargeAccount < Write\nend\n",
    "app/reads/list_people.rb" => "class ListPeople < Read\nend\n",
    "app/io/io_send_invoice.rb" => "class IoSendInvoice < IoWrite\nend\n",
    "app/io/io_fetch_rates.rb" => "class IoFetchRates < IoRead\nend\n",
    "app/shapes/money.rb" => "class Money < Shape\nend\n",
    "app/records/invoice_record.rb" => "class InvoiceRecord < ApplicationRecord\nend\n",
  }.freeze

  def test_a_write_may_not_write_to_the_outside
    found = check(<<~RUBY, "app/writes/charge_account.rb")
      class ChargeAccount < Write
        def call
          IoSendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A write may not call an io_write"
    assert_includes found.first.message, "They are sisters",
      "The rule this whole split exists for."
  end

  def test_a_write_may_not_read_from_the_outside
    found = check(<<~RUBY, "app/writes/charge_account.rb")
      class ChargeAccount < Write
        def call
          IoFetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A write may not call an io_read",
      "And not read from it either: the transaction is held open just the same by a read."
  end

  def test_a_read_may_not_read_from_the_outside
    found = check(<<~RUBY, "app/reads/list_people.rb")
      class ListPeople < Read
        def call
          IoFetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A read may not call an io_read"
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

  def test_the_two_io_kinds_are_told_apart_by_their_base_class
    found = check(<<~RUBY, "app/io/io_fetch_rates.rb")
      class IoFetchRates < IoRead
        def call
          IoSendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_read may not call an io_write",
      "Two kinds, one tree, told apart by what they inherit — the same mechanism as the legacy doors, so the `Io` prefix marks the call site and the base class carries the shape."
  end

  def test_an_io_write_may_not_write_to_the_local_store
    found = check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoWrite
        def call
          InvoiceRecord.create!
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_write may not call a record",
      "It touches no record: the external call and the write recording its result are two steps, so a failed remote call leaves no half-written row behind."
  end

  # A write may read first — fetching a token before posting. The read it may do is the one
  # in its own world, mirroring `write -> read`.
  def test_an_io_write_may_read_from_the_outside
    assert_empty check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoWrite
        def call
          IoFetchRates.call
        end
      end
    RUBY
  end

  def test_an_io_write_may_not_read_the_local_store
    found = check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoWrite
        def call
          ListPeople.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_write may not call a read",
      "Reaching back across the boundary it just crossed. Anything it needs from here should have been handed to it, like every other input."
  end

  def test_an_io_operation_may_build_shapes
    assert_empty check(<<~RUBY, "app/io/io_fetch_rates.rb")
      class IoFetchRates < IoRead
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
