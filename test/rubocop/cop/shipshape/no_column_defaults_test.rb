# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `default_option` answer nil reddens every offence test.
# - Emptying `TIMESTAMPS` reddens the timestamp test, which is the law's one exception.
# - Making `column_of` ignore `ADDERS` reddens the add_column naming test.
class NoColumnDefaultsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoColumnDefaults

  PATH = "db/migrate/20260101000000_add_state_to_bookings.rb"

  def test_a_column_default_is_an_offence
    found = check(<<~RUBY)
      class AddStateToBookings < ActiveRecord::Migration[7.0]
        def change
          create_table :bookings do |t|
            t.string :state, null: false, default: "held"
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, '`state` carries a database default of `"held"`'
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class AddStateToBookings < ActiveRecord::Migration[7.0]
        def change
          create_table :bookings do |t|
            t.string :state, null: false, default: "held"
          end
        end
      end
    RUBY

    assert_includes message, "WHY: The domain already names the fallback"
    assert_includes message, "INSTEAD:"
    assert_includes message, "t.string :state, null: false"
  end

  def test_add_column_names_the_column_not_the_table
    found = check(<<~RUBY)
      class AddStateToBookings < ActiveRecord::Migration[7.0]
        def change
          add_column :bookings, :state, :string, default: "held"
        end
      end
    RUBY

    assert_includes found.first.message, "`state` carries a database default"
  end

  def test_no_default_is_the_shape
    assert_empty check(<<~RUBY)
      class AddStateToBookings < ActiveRecord::Migration[7.0]
        def change
          create_table :bookings do |t|
            t.string :state, null: false
          end
        end
      end
    RUBY
  end

  # The law's one exception, written down.
  def test_timestamps_are_excepted
    assert_empty check(<<~RUBY)
      class AddStateToBookings < ActiveRecord::Migration[7.0]
        def change
          add_column :bookings, :created_at, :datetime, default: -> { "CURRENT_TIMESTAMP" }
          add_column :bookings, :updated_at, :datetime, default: -> { "CURRENT_TIMESTAMP" }
        end
      end
    RUBY
  end

  def test_a_false_default_is_still_a_default
    assert_equal 1, check(<<~RUBY).length
      class AddStateToBookings < ActiveRecord::Migration[7.0]
        def change
          t.boolean :archived, null: false, default: false
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
