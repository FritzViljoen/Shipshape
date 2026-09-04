# frozen_string_literal: true

require "test_helper"
require "shipshape/measures/duplicated_columns"

class Shipshape::Measures::DuplicatedColumnsTest < Minitest::Test
  DuplicatedColumns = Shipshape::Measures::DuplicatedColumns

  def test_a_pair_duplicated_across_three_tables_is_found
    labels = labels_in(<<~RUBY)
      create_table "orders" do |t|
        t.string "currency"
        t.decimal "amount"
        t.string "reference"
      end

      create_table "invoices" do |t|
        t.string "currency"
        t.decimal "amount"
        t.string "number"
      end

      create_table "refunds" do |t|
        t.string "currency"
        t.decimal "amount"
      end

      create_table "widgets" do |t|
        t.string "name"
      end
    RUBY

    assert_equal ["amount, currency — on 3 tables: invoices, orders, refunds"], labels
  end

  def test_two_tables_sharing_a_group_is_a_coincidence_not_a_finding
    labels = labels_in(<<~RUBY)
      create_table "orders" do |t|
        t.string "currency"
        t.decimal "amount"
      end

      create_table "invoices" do |t|
        t.string "currency"
        t.decimal "amount"
      end
    RUBY

    assert_empty labels, "Two is a coincidence; three is a table."
  end

  def test_a_single_recurring_column_is_never_enough_alone
    labels = labels_in(<<~RUBY)
      create_table "orders" do |t|
        t.string "currency"
      end

      create_table "invoices" do |t|
        t.string "currency"
      end

      create_table "refunds" do |t|
        t.string "currency"
      end
    RUBY

    assert_empty labels, "One column recurring alone is the noisiest possible shape; it takes a group."
  end

  def test_the_largest_group_is_reported_once_not_as_every_smaller_pair_inside_it
    labels = labels_in(<<~RUBY)
      create_table "users" do |t|
        t.string "street"
        t.string "city"
        t.string "postal_code"
      end

      create_table "suppliers" do |t|
        t.string "street"
        t.string "city"
        t.string "postal_code"
      end

      create_table "bookings" do |t|
        t.string "street"
        t.string "city"
        t.string "postal_code"
      end
    RUBY

    assert_equal ["city, postal_code, street — on 3 tables: bookings, suppliers, users"], labels,
      "A five-way address has ten pairs inside it; only the maximal group may render."
  end

  def test_rails_bookkeeping_columns_are_excluded_even_when_they_recur
    labels = labels_in(<<~RUBY)
      create_table "orders" do |t|
        t.integer "lock_version"
        t.string "type"
      end

      create_table "invoices" do |t|
        t.integer "lock_version"
        t.string "type"
      end

      create_table "refunds" do |t|
        t.integer "lock_version"
        t.string "type"
      end
    RUBY

    assert_empty labels, "id, created_at, updated_at, lock_version and type are declared exempt " \
                         "and would otherwise fire on nearly every table in an application."
  end

  def test_a_type_mismatch_breaks_the_match
    labels = labels_in(<<~RUBY)
      create_table "orders" do |t|
        t.string "code"
        t.decimal "amount"
      end

      create_table "invoices" do |t|
        t.string "code"
        t.decimal "amount"
      end

      create_table "refunds" do |t|
        t.integer "code"
        t.decimal "amount"
      end
    RUBY

    assert_empty labels, "code is a string on two tables and an integer on the third, so the " \
                         "pair only agrees on two tables — a coincidence, not yet a pattern."
  end

  def test_population_counts_every_declared_column
    population = in_schema(<<~RUBY) { |root| DuplicatedColumns.new(root: root).population([]) }
      create_table "orders" do |t|
        t.string "currency"
        t.decimal "amount"
        t.datetime "created_at"
      end
    RUBY

    assert_equal 3, population
  end

  def test_units_counts_column_line_instances_not_findings
    found = in_schema(<<~RUBY) { |root| DuplicatedColumns.new(root: root).call([]) }
      create_table "orders" do |t|
        t.string "currency"
        t.decimal "amount"
      end

      create_table "invoices" do |t|
        t.string "currency"
        t.decimal "amount"
      end

      create_table "refunds" do |t|
        t.string "currency"
        t.decimal "amount"
      end
    RUBY

    measure = DuplicatedColumns.new(root: "unused")
    assert_equal 1, found.length
    assert_equal 6, measure.units(found), "2 columns on 3 tables is 6 duplicated column lines, not 1 finding."
  end

  private

  def labels_in(body)
    in_schema(body) { |root| DuplicatedColumns.new(root: root).call([]) }.map(&:label)
  end

  def in_schema(body)
    Dir.mktmpdir("duplicated-columns") do |root|
      target = File.join(root, "db/schema.rb")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, <<~RUBY)
        ActiveRecord::Schema[8.0].define(version: 1) do
          #{body}
        end
      RUBY

      yield(root)
    end
  end
end
