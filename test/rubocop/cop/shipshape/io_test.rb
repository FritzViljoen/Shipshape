# frozen_string_literal: true

require "test_helper"

# Reading and changing state outside this process. Same two operations as the internal pair,
# marked, and sisters of it — so a deed may not do IO.
class IoTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "workflow" => ["app/workflows/**/*.rb"],
      "deed" => ["app/deeds/**/*.rb"],
      "question" => ["app/questions/**/*.rb"],
      "io_question" => ["app/io/**/*.rb"],
      "io_deed" => ["app/io/**/*.rb"],
      "shape" => ["app/shapes/**/*.rb"],
      "record" => ["app/records/**/*_record.rb"],
    },
    "BaseClasses" => {
      "workflow" => ["Workflow"],
      "deed" => ["Deed"],
      "question" => ["Question"],
      "io_question" => ["IoQuestion"],
      "io_deed" => ["IoDeed"],
      "shape" => ["Shape"],
      "record" => ["ApplicationRecord"],
    },
    "Sisters" => [%w[deed io_deed], %w[question io_question]],
    "Matrix" => {
      "workflow" => %w[deed question io_deed io_question shape],
      "deed" => %w[question shape record],
      "question" => %w[shape record],
      "io_deed" => %w[io_question shape],
      "io_question" => ["shape"],
      "shape" => [],
      "record" => [],
    },
  }.freeze

  TREE = {
    "app/workflows/settle_month.rb" => "class SettleMonth < Workflow\nend\n",
    "app/deeds/charge_account.rb" => "class ChargeAccount < Deed\nend\n",
    "app/questions/list_people.rb" => "class ListPeople < Question\nend\n",
    "app/io/io_send_invoice.rb" => "class IoSendInvoice < IoDeed\nend\n",
    "app/io/io_fetch_rates.rb" => "class IoFetchRates < IoQuestion\nend\n",
    "app/shapes/money.rb" => "class Money < Shape\nend\n",
    "app/records/invoice_record.rb" => "class InvoiceRecord < ApplicationRecord\nend\n",
  }.freeze

  def test_a_deed_may_not_write_to_the_outside
    found = check(<<~RUBY, "app/deeds/charge_account.rb")
      class ChargeAccount < Deed
        def call
          IoSendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A deed may not call an io_deed"
    assert_includes found.first.message, "They are sisters",
      "The rule this whole split exists for."
  end

  def test_a_deed_may_not_read_from_the_outside
    found = check(<<~RUBY, "app/deeds/charge_account.rb")
      class ChargeAccount < Deed
        def call
          IoFetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A deed may not call an io_question",
      "And not read from it either: the transaction is held open just the same by a read."
  end

  def test_a_question_may_not_read_from_the_outside
    found = check(<<~RUBY, "app/questions/list_people.rb")
      class ListPeople < Question
        def call
          IoFetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A question may not call an io_question"
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
      class IoFetchRates < IoQuestion
        def call
          IoSendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_question may not call an io_deed",
      "Two kinds, one tree, told apart by what they inherit — the same mechanism as the legacy doors, so the `Io` prefix marks the call site and the base class carries the shape."
  end

  def test_an_io_deed_may_not_write_to_the_local_store
    found = check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoDeed
        def call
          InvoiceRecord.create!
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_deed may not call a record",
      "It touches no record: the external call and the write recording its result are two steps, so a failed remote call leaves no half-written row behind."
  end

  # A write may read first — fetching a token before posting. The read it may do is the one
  # in its own world, mirroring `deed -> question`.
  def test_an_io_deed_may_read_from_the_outside
    assert_empty check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoDeed
        def call
          IoFetchRates.call
        end
      end
    RUBY
  end

  def test_an_io_deed_may_not_read_the_local_store
    found = check(<<~RUBY, "app/io/io_send_invoice.rb")
      class IoSendInvoice < IoDeed
        def call
          ListPeople.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An io_deed may not call a question",
      "Reaching back across the boundary it just crossed. Anything it needs from here should have been handed to it, like every other input."
  end

  def test_an_io_operation_may_build_shapes
    assert_empty check(<<~RUBY, "app/io/io_fetch_rates.rb")
      class IoFetchRates < IoQuestion
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
