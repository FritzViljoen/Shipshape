# frozen_string_literal: true

require "test_helper"

# Watched to fail: removing the `Kinds` default reddens the workflow and read tests; a bang
# form reddens every offence test; dropping the block check reddens the false-positive tests
# below, none of which write a block; dropping the receiver check reddens the last one, which does.
class OperationsOpenNoTransactionTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OperationsOpenNoTransaction

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "write" => ["app/writes/**/*.rb"],
        "read" => ["app/reads/**/*.rb"],
        "workflow" => ["app/workflows/**/*.rb"],
        "io_read" => ["app/io_reads/**/*.rb"],
        "record" => ["app/records/**/*_record.rb"],
      },
      "BaseClasses" => { "record" => %w[ApplicationRecord ActiveRecord::Base] },
      "Matrix" => {
        "write" => [], "read" => [], "workflow" => ["write"], "io_read" => [], "record" => [],
      },
    },
  }.freeze

  TREE = {
    "app/records/booking_record.rb" => "class BookingRecord < ApplicationRecord\nend\n",
  }.freeze

  def test_a_write_opening_a_transaction_is_an_offence
    found = check(<<~RUBY, path: "app/writes/confirm_booking.rb")
      class ConfirmBooking < Write
        def call
          ActiveRecord::Base.transaction do
            @booking.confirm!
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`transaction` opens a transaction of its own"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY, path: "app/writes/confirm_booking.rb").first.message
      class ConfirmBooking < Write
        def call
          transaction { @booking.confirm! }
        end
      end
    RUBY

    assert_includes message, "WHY: The generated base class wraps the call in exactly one"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class ConfirmBooking < Write"
  end

  def test_a_read_opening_a_transaction_is_an_offence
    found = check(<<~RUBY, path: "app/reads/find_booking.rb")
      class FindBooking < Read
        def call
          BookingRecord.transaction { BookingRecord.find(@id) }
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  def test_a_workflow_opening_a_transaction_is_an_offence
    found = check(<<~RUBY, path: "app/workflows/settle_order.rb")
      class SettleOrder < Workflow
        def call
          ActiveRecord::Base.transaction { ChargeCard.call }
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "WHY: A workflow sequences several transactions"
  end

  def test_an_operation_with_no_transaction_is_the_shape
    assert_empty check(<<~RUBY, path: "app/writes/confirm_booking.rb")
      class ConfirmBooking < Write
        def call
          @booking.confirm!
          success(@booking)
        end
      end
    RUBY
  end

  # A record is a different kind, unnamed by this cop's default `Kinds`.
  def test_a_record_is_not_governed
    assert_empty check(<<~RUBY, path: "app/records/booking_record.rb")
      class BookingRecord < ApplicationRecord
        def self.confirm_all
          transaction { update_all(state: "confirmed") }
        end
      end
    RUBY
  end

  # Reported by review: a payment gateway's own API, once refused by the receiver-blind matcher.
  def test_a_same_named_read_on_a_gateway_is_left_alone
    assert_empty check(<<~RUBY, path: "app/io_reads/charge_status.rb")
      class ChargeStatus < IoRead
        def call
          success(@gateway.transaction(@reference))
        end
      end
    RUBY
  end

  # Reported by review: an association named `transaction`, which opens nothing.
  def test_a_same_named_association_is_left_alone
    assert_empty check(<<~RUBY, path: "app/writes/reverse_charge.rb")
      class ReverseCharge < Write
        def call
          @payment.transaction.reverse!
          success(@payment)
        end
      end
    RUBY
  end

  # Reported by review: an attr_reader named `transaction`, called with no block at all.
  def test_a_same_named_attr_reader_is_left_alone
    assert_empty check(<<~RUBY, path: "app/reads/find_charge.rb")
      class FindCharge < Read
        attr_reader :transaction

        def call
          transaction.reference
        end
      end
    RUBY
  end

  # Reported by review: `Kinds` is a documented knob, and an app may point this cop at a kind
  # neither `BECAUSE` nor `INSTEAD` names — `BECAUSE.fetch(kind)` raised `KeyError` here before
  # the generic fallback existed.
  def test_an_app_configured_kind_with_no_reason_on_file_gets_the_generic_one
    layout = LAYOUT.merge(
      "Shipshape/CallGraph" => LAYOUT["Shipshape/CallGraph"].merge(
        "Kinds" => LAYOUT["Shipshape/CallGraph"]["Kinds"].merge("shape" => ["app/shapes/**/*.rb"]),
      ),
    )

    found = offences(
      <<~RUBY,
        class Booking < Shape
          def call
            ActiveRecord::Base.transaction { @thing.save! }
          end
        end
      RUBY
      cop_class: COP,
      cop_config: { "Kinds" => %w[shape] },
      path: "app/shapes/booking.rb",
      other_cops: layout,
    )

    assert_equal 1, found.length
    assert_includes found.first.message, "An operation opens no transaction of its own."
  end

  # The gateway read above, with a block attached: proves the fix is the receiver, not the block.
  def test_a_block_call_on_a_non_record_receiver_is_left_alone
    assert_empty check(<<~RUBY, path: "app/writes/reverse_charge.rb")
      class ReverseCharge < Write
        def call
          @gateway.transaction(@reference) { |t| t.reverse! }
          success(@payment)
        end
      end
    RUBY
  end

  private

  def check(source, path:)
    offences(source, cop_class: COP, path: path, other_cops: LAYOUT, files: TREE)
  end
end
