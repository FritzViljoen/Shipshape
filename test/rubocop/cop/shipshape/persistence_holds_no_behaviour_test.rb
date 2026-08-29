# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `on_def` return early reddens the instance-method test.
# - Making `on_defs` return early reddens the class-method test.
# - Making `reaches_another_class?` answer true reddens the filtering-scope test, which is
#   the shape the law explicitly allows.
class PersistenceHoldsNoBehaviourTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::PersistenceHoldsNoBehaviour

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "record" => ["app/records/**/*_record.rb"],
        "query" => ["app/queries/**/*.rb"],
      },
      "Matrix" => { "record" => [], "query" => ["record"] },
    },
  }.freeze

  RECORD = "app/records/booking_record.rb"

  def test_a_method_on_a_record_is_behaviour
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        def total
          lines.sum(&:amount)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`#total` is behaviour on a record"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class BookingRecord < ApplicationRecord
        def total
          lines.sum(&:amount)
        end
      end
    RUBY

    assert_includes message, "WHY: A method here is reachable from everywhere a record is"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class TotalBooking < Query"
  end

  def test_a_class_method_is_behaviour_too
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        def self.settle_all
          all.each(&:settle)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`.settle_all` is behaviour"
  end

  def test_columns_and_associations_are_the_shape
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        self.table_name = "bookings"

        belongs_to :supplier_record
        has_many :line_records

        validates :reference, presence: true
      end
    RUBY
  end

  # The law allows a scope that filters on this table's own columns.
  def test_a_filtering_scope_is_allowed
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        scope :recent, -> { where("created_at > ?", 30) }
      end
    RUBY
  end

  def test_a_scope_reaching_another_class_carries_a_rule
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        scope :billable, -> { joins(:supplier_record).merge(SupplierRecord.active) }
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "carries a rule rather than a filter"
  end

  # Still behaviour, but not reachable from everywhere a record is.
  def test_a_private_helper_is_not_the_harm_this_names
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        private

        def normalise
          reference.strip
        end
      end
    RUBY
  end

  def test_a_query_may_hold_all_the_behaviour_it_likes
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/queries/total_booking.rb", other_cops: LAYOUT)
      class TotalBooking
        def call
          success(@lines.sum(&:amount))
        end
      end
    RUBY
  end

  # A constant used as a value is a filter on this table's own column, which the law
  # explicitly permits. Failing it was this cop's worst false positive.
  def test_a_scope_filtering_on_a_value_constant_is_allowed
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        scope :active, -> { where(state: Booking::ACTIVE) }
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: RECORD, other_cops: LAYOUT)
  end
end
