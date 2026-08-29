# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `null_option` answer nil reddens every offence test.
# - Making `promotions_in` answer `[]` reddens the promotion test, which is the clause that
#   makes the rule workable on a populated table.
# - Making `reversing?` answer false reddens the `down` and `remove_column` tests.
class NoNullableColumnsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoNullableColumns

  PATH = "db/migrate/20260101000000_add_nickname_to_people.rb"

  def test_a_nullable_column_in_a_table_body_is_an_offence
    found = check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          create_table :people do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`nickname` is nullable"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          add_column :people, :nickname, :string, null: true
        end
      end
    RUBY

    assert_includes message, 'WHY: A null is not "off", not "inherit"'
    assert_includes message, "INSTEAD:"
    assert_includes message, "add_index :person_nicknames, :person_id, unique: true"
  end

  def test_a_not_null_column_is_the_shape
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          create_table :people do |t|
            t.string :nickname, null: false
          end
        end
      end
    RUBY
  end

  # The clause that makes the law workable on a populated table.
  def test_a_column_promoted_in_the_same_method_passes
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def up
          add_column :people, :nickname, :string, null: true
          PersonRecord.update_all(nickname: "")
          change_column_null :people, :nickname, false
        end
      end
    RUBY
  end

  def test_a_different_column_promoted_does_not_excuse_this_one
    assert_equal 1, check(<<~RUBY).length
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def up
          add_column :people, :nickname, :string, null: true
          change_column_null :people, :other, false
        end
      end
    RUBY
  end

  def test_the_reverse_direction_is_exempt
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def down
          change_column_null :people, :nickname, true
        end
      end
    RUBY
  end

  def test_a_reference_is_resolved_to_the_column_it_creates
    found = check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          add_reference :bookings, :supplier, null: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`supplier` is nullable"
  end

  # The case the cop missed entirely at first: a column with no `null:` is nullable, and
  # that is how nearly every nullable column arrives.
  def test_a_column_that_says_nothing_is_nullable
    found = check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          create_table :people do |t|
            t.string :nickname
            t.integer :age
          end
          add_column :people, :note, :string
        end
      end
    RUBY

    assert_equal 3, found.length
    assert_includes found.first.message, "says nothing about `null:`, which means nullable"
  end

  def test_declarations_that_are_not_columns_are_left_alone
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          create_table :people do |t|
            t.timestamps
            t.index :reference
          end
        end
      end
    RUBY
  end

  def test_change_column_names_the_column_not_the_table
    found = check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          change_column :people, :state, :string, null: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`state` is nullable"
  end

  def test_change_column_is_promoted_by_the_same_method
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def up
          change_column :people, :state, :string, null: true
          change_column_null :people, :state, false
        end
      end
    RUBY
  end

  # A promotion built in a loop cannot be read, so the addition beside it is not reported
  # either. A guard that cannot see the promotion must not fail the addition.
  def test_a_non_literal_column_is_skipped_rather_than_crashed_on
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        COLUMNS = %i[nickname alias_name].freeze

        def up
          COLUMNS.each do |column|
            add_column :people, column, :string, null: true
            PersonRecord.update_all(column => "")
            change_column_null :people, column, false
          end
        end
      end
    RUBY
  end

  # A cop that raises leaves the file reported as clean. And once it stopped raising it
  # reported "says nothing about null:" over a column that says `null: false` — unreadable
  # is not absent.
  def test_a_non_literal_hash_key_does_not_crash_the_cop
    assert_empty check(<<~RUBY)
      class AddNicknameToPeople < ActiveRecord::Migration[7.0]
        def change
          add_column :people, :nickname, :string, NULL => false
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
