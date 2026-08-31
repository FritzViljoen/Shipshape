# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `on_def` return early reddens the instance-method test.
# - Making `on_defs` return early reddens the class-method test.
# - Making `reaches_another_class?` answer true reddens the filtering-scope test, which is
#   the shape the law explicitly allows.
# - Dropping the `DELEGATORS` branch reddens the two public `delegate` tests.
# - Making `public_delegate?` answer true reddens the private-delegate test.
# - Dropping the `default_scope` branch reddens three of the four `default_scope` tests.
#   The fourth asserts silence outside the record tree, so it stays green — which is what
#   makes it the false-positive guard rather than a fourth copy of the same assertion.
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

  def test_delegate_puts_methods_on_a_record
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        belongs_to :supplier_record
        delegate :name, :email, to: :supplier_record
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`delegate` puts public methods on a record",
      "**`delegate` was the one way left to put behaviour on a record.** `def name; supplier.name; end` is an offence; the macro writes the same method and the guard reading `def` saw nothing. `code-is-written-not-generated` exempts it deliberately — that law draws its line at the framework's public conventions — which decides where it is caught, not whether."
  end

  # **Judged on visibility, the way a `def` already is.** `on_def` exempts a private method
  # because it is not reachable from everywhere a record is; flagging the macro spelling and
  # not the handwritten one made the rule depend on which was used.
  def test_a_private_delegate_is_exempt_like_a_private_def
    assert_empty check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        delegate :name, to: :supplier_record, private: true
      end
    RUBY
  end

  # The same surface with no list at all, so it cannot even be read off the declaration.
  def test_delegate_missing_to_is_the_same_offence
    assert_equal 1, check(<<~RUBY).length
      class BookingRecord < ApplicationRecord
        delegate_missing_to :supplier_record
      end
    RUBY
  end

  # The line the other law draws stays where it is: a delegating operation is that cop's
  # business and not this one's, and neither of them is the record tree.
  def test_delegate_outside_a_record_is_not_this_cops_business
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/queries/list_bookings.rb", other_cops: LAYOUT)
      class ListBookings < Query
        delegate :name, to: :supplier
      end
    RUBY
  end

  def test_a_default_scope_is_a_rule_on_every_read
    found = check(<<~RUBY)
      class BookingRecord < ApplicationRecord
        default_scope { where(cancelled_at: nil) }
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "implicit behaviour: global state on every read",
      "**`default_scope` was invisible to this cop**, which matched `scope` exactly — so the one scope reaching every read in the application passed the guard that exists to stop rules living on records. Found by surveying the canon against a list of Rails failures it did not write."
  end

  # A named scope is judged on whether it reaches another class. This one is not: it needs no
  # other class to be a rule, because it is a rule about reads nobody wrote.
  def test_a_default_scope_touching_only_its_own_columns_is_still_an_offence
    assert_equal 1, check(<<~RUBY).length
      class BookingRecord < ApplicationRecord
        default_scope { order(created_at: :desc) }
      end
    RUBY
  end

  def test_the_default_scope_offence_names_create_and_offers_a_named_query
    message = check(<<~RUBY).first.message
      class BookingRecord < ApplicationRecord
        default_scope { where(cancelled_at: nil) }
      end
    RUBY

    assert_includes message, "WHY:"
    assert_includes message, "nothing-travels-off-the-call-path"
    assert_includes message, "sets attributes on `create`"
    assert_includes message, "class ListLiveBookings < Query"
  end

  # The kind decides, as everywhere. A `default_scope` is not a shape this cop hunts outside
  # the record tree.
  def test_a_default_scope_outside_a_record_is_not_this_cops_business
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/queries/list_bookings.rb", other_cops: LAYOUT)
      class ListBookings < Query
        default_scope { where(cancelled_at: nil) }
      end
    RUBY
  end

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
