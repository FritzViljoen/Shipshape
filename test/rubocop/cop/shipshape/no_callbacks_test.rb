# frozen_string_literal: true

require "test_helper"

# Watched to fail, as `a-guard-states-its-limit` requires:
#
# - Emptying `HOOKS` reddens every offence test.
# - Making `one_of?` answer true unconditionally reddens the command test.
# - Dropping the `node.receiver.nil?` check reddens the explicit-receiver test.
class NoCallbacksTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoCallbacks

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "record" => ["app/records/**/*_record.rb"],
        "command" => ["app/commands/**/*.rb"],
      },
      "Matrix" => { "record" => [], "command" => ["record"] },
    },
  }.freeze

  RECORD = "app/records/booking_record.rb"

  def test_a_registration_is_an_offence
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        before_save :recalculate_totals
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`before_save` hides work behind `save`"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class BookingRecord < ApplicationRecord
        after_commit :notify
      end
    RUBY

    assert_includes message, "WHY: The caller reads one method and gets several"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class ConfirmBooking < Command"
  end

  def test_every_hook_in_the_family_is_caught
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        before_validation :normalise
        around_create :instrument
        after_destroy :clean_up
        after_rollback :report
      end
    RUBY

    assert_equal 4, found.length
  end

  def test_a_record_with_no_callbacks_is_the_shape
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        belongs_to :customer_record
      end
    RUBY
  end

  # `subscriber.after_commit { ... }` is a method on something else, not a registration.
  def test_a_call_with_a_receiver_is_not_a_registration
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        def self.watch(subscriber)
          subscriber.after_commit(:notify)
        end
      end
    RUBY
  end

  # The rule is about records. A command naming one of these words is its own method.
  def test_a_command_is_not_a_record
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/commands/confirm_booking.rb", other_cops: LAYOUT)
      class ConfirmBooking
        def call
          after_save
        end
      end
    RUBY
  end

  # The law forbids "after-commit or any of their siblings" by name.
  def test_the_commit_shorthands_are_siblings_and_are_caught
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        after_create_commit :a
        after_update_commit :b
        after_destroy_commit :c
        after_save_commit :d
      end
    RUBY

    assert_equal 4, found.length
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: RECORD, other_cops: LAYOUT)
  end
end
