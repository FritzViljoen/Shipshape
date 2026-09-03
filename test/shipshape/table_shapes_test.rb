# frozen_string_literal: true

require "test_helper"
require "shipshape/table_shapes"

# Watched to fail: dropping the single-column guard in `add_unique`/`add_top_level_unique`
# makes the composite-index test's key read as unique; skipping the `column:` fallback reddens
# the default-inference test; treating `nullable` columns as blank-sentinel-capable reddens
# that test too; blurring any of the four `shape_of` counts collapses two of its tests together.
class TableShapesTest < Minitest::Test
  def test_no_schema_reports_no_tables
    Dir.mktmpdir("table-shapes") do |root|
      assert_empty Shipshape::TableShapes.new(root: root).call
    end
  end

  def test_nullable_columns_are_named_and_every_column_is_counted
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "customer_note"
        t.string "state", null: false
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
      end
    RUBY

    assert_equal 4, orders.column_count
    assert_equal ["customer_note"], orders.nullable
  end

  def test_a_boolean_cluster_is_named
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.boolean "paid", default: false
        t.boolean "refunded", default: false
        t.string "state", null: false
      end
    RUBY

    assert_equal %w[paid refunded], orders.booleans
  end

  def test_status_shaped_columns_are_named
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
        t.string "fulfillment_status", null: false
        t.string "customer_note"
      end
    RUBY

    assert_equal %w[state fulfillment_status], orders.status_shaped
  end

  def test_a_not_null_string_can_still_carry_a_blank_sentinel
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "discount_code", null: false, default: ""
        t.string "state", null: false
        t.integer "quantity", null: false
        t.string "note"
      end
    RUBY

    assert_equal %w[discount_code state], orders.blank_sentinel_capable.map(&:name)
    assert_equal "\"\"", orders.blank_sentinel_capable.first.default
  end

  def test_a_nullable_column_is_not_also_named_as_blank_sentinel_capable
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "note"
      end
    RUBY

    assert_empty orders.blank_sentinel_capable
  end

  def test_an_ordinary_foreign_key_unlocks_cardinality
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_lines", force: :cascade do |t|
        t.bigint "order_id", null: false
        t.string "sku"
        t.index ["order_id"], name: "index_order_lines_on_order_id"
      end

      add_foreign_key "order_lines", "orders"
    RUBY

    neighbour = orders.neighbours.first
    refute neighbour.unique, "An unindexed-for-uniqueness foreign key is an ordinary one-to-many."
    assert_equal :unlocked_cardinality, neighbour.shape
  end

  # A composite unique index makes no single column unique on its own — this is the case
  # `add_unique`'s length check exists for, and it reads the same as no index at all.
  def test_a_composite_unique_index_still_reads_as_unlocked_cardinality
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_lines", force: :cascade do |t|
        t.bigint "order_id", null: false
        t.integer "position", null: false
        t.index ["order_id", "position"], name: "index_order_lines_on_order_id_and_position", unique: true
      end

      add_foreign_key "order_lines", "orders"
    RUBY

    assert_equal :unlocked_cardinality, orders.neighbours.first.shape
  end

  def test_a_unique_key_back_with_one_nullable_column_unlocks_nothing
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_shipping_details", force: :cascade do |t|
        t.bigint "order_id", null: false
        t.string "address"
        t.index ["order_id"], name: "index_order_shipping_details_on_order_id", unique: true
      end

      add_foreign_key "order_shipping_details", "orders"
    RUBY

    neighbour = orders.neighbours.first
    assert_equal "order_shipping_details", neighbour.table
    assert neighbour.unique
    assert_equal :unlocked_nothing, neighbour.shape,
      "A unique key back plus one nullable column is a renamed column with extra steps."
  end

  def test_a_custom_primary_key_also_makes_a_neighbour_unique
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_shipping_details", primary_key: "order_id", force: :cascade do |t|
        t.string "address"
      end

      add_foreign_key "order_shipping_details", "orders"
    RUBY

    neighbour = orders.neighbours.first
    assert neighbour.unique
    assert_equal :unlocked_nothing, neighbour.shape
  end

  def test_two_or_more_not_null_columns_beside_the_key_unlocks_a_composite_fact
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_cancellations", primary_key: "order_id", force: :cascade do |t|
        t.string "reason", null: false
        t.bigint "cancelled_by_id", null: false
        t.datetime "cancelled_at", null: false
      end

      add_foreign_key "order_cancellations", "orders"
    RUBY

    assert_equal :unlocked_composite_fact, orders.neighbours.first.shape
  end

  # Exactly one required column beside the key, no null anywhere: the shape
  # `a-nullable-column.md` calls the fix, distinct from "unlocked nothing" by one `null: false`.
  def test_exactly_one_not_null_column_beside_the_key_unlocks_absence
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_confirmations", primary_key: "order_id", force: :cascade do |t|
        t.bigint "confirmed_by_id", null: false
      end

      add_foreign_key "order_confirmations", "orders"
    RUBY

    assert_equal :unlocked_absence, orders.neighbours.first.shape
  end

  def test_two_or_more_not_null_columns_still_beats_the_single_column_absence_check
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_confirmations", primary_key: "order_id", force: :cascade do |t|
        t.bigint "confirmed_by_id", null: false
        t.datetime "confirmed_at", null: false
      end

      add_foreign_key "order_confirmations", "orders"
    RUBY

    assert_equal :unlocked_composite_fact, orders.neighbours.first.shape
  end

  # Neither named pattern: two nullable columns beside the key, none of them required. Left
  # unlabelled rather than forced into "nothing" or "composite fact" — the caller reads the
  # raw columns and decides which it is.
  def test_a_shape_matching_neither_named_pattern_is_left_unlabelled
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_billing_details", primary_key: "order_id", force: :cascade do |t|
        t.string "vat_number"
        t.string "billing_address"
      end

      add_foreign_key "order_billing_details", "orders"
    RUBY

    neighbour = orders.neighbours.first
    assert_nil neighbour.shape
    assert_equal %w[vat_number billing_address], neighbour.other_columns
  end

  def test_an_explicit_non_default_column_is_read_over_the_rails_default
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
      end

      create_table "order_returns", force: :cascade do |t|
        t.bigint "original_order_id", null: false
        t.string "reason"
        t.index ["original_order_id"], name: "index_order_returns_on_original_order_id", unique: true
      end

      add_foreign_key "order_returns", "orders", column: "original_order_id"
    RUBY

    neighbour = orders.neighbours.first
    assert_equal "original_order_id", neighbour.column
    assert neighbour.unique
  end

  def test_a_nullable_column_no_migration_declares_is_migration_blind
    orders = table(<<~RUBY).fetch("orders")
      create_table "orders", force: :cascade do |t|
        t.string "state", null: false
        t.string "supplier_note"
      end
    RUBY

    assert_equal ["supplier_note"], orders.migration_blind,
      "No db/migrate directory at all: nothing declares this column, so AbsenceIsAbsenceNeverAValue never saw it."
  end

  def test_a_column_added_by_add_column_is_not_migration_blind
    orders = table_with_migrations(
      <<~SCHEMA,
        create_table "orders", force: :cascade do |t|
          t.string "state", null: false
          t.string "supplier_note"
        end
      SCHEMA
      "20200101000000_add_supplier_note.rb" => <<~RUBY,
        class AddSupplierNote < ActiveRecord::Migration[5.2]
          def change
            add_column :orders, :supplier_note, :string
          end
        end
      RUBY
    ).fetch("orders")

    assert_empty orders.migration_blind
  end

  def test_a_column_declared_inside_a_create_table_block_is_not_migration_blind
    orders = table_with_migrations(
      <<~SCHEMA,
        create_table "orders", force: :cascade do |t|
          t.string "state", null: false
          t.string "supplier_note"
        end
      SCHEMA
      "20200101000000_create_orders.rb" => <<~RUBY,
        class CreateOrders < ActiveRecord::Migration[5.2]
          def change
            create_table :orders do |t|
              t.string :state, null: false
              t.string :supplier_note
            end
          end
        end
      RUBY
    ).fetch("orders")

    assert_empty orders.migration_blind
  end

  def test_a_reference_column_is_matched_under_its_id_suffixed_name
    orders = table_with_migrations(
      <<~SCHEMA,
        create_table "orders", force: :cascade do |t|
          t.string "state", null: false
          t.bigint "customer_id"
        end
      SCHEMA
      "20200101000000_add_customer.rb" => <<~RUBY,
        class AddCustomer < ActiveRecord::Migration[5.2]
          def change
            add_reference :orders, :customer
          end
        end
      RUBY
    ).fetch("orders")

    assert_empty orders.migration_blind
  end

  # Two blocks, two tables, two block vars in one file: a column line is matched to the block
  # it is actually inside, not to whichever table a migration happened to mention last.
  def test_a_second_blocks_columns_are_not_attributed_to_the_first_tables_block_var
    tables = table_with_migrations(
      <<~SCHEMA,
        create_table "orders", force: :cascade do |t|
          t.string "state", null: false
        end

        create_table "customers", force: :cascade do |t|
          t.string "name"
        end
      SCHEMA
      "20200101000000_create_both.rb" => <<~RUBY,
        class CreateBoth < ActiveRecord::Migration[5.2]
          def change
            create_table :orders do |o|
              o.string :state, null: false
            end

            create_table :customers do |c|
              c.string :name
            end
          end
        end
      RUBY
    )

    assert_empty tables.fetch("customers").migration_blind
  end

  private

  def table(schema)
    table_with_migrations(schema, {})
  end

  def table_with_migrations(schema, migrations)
    Dir.mktmpdir("table-shapes") do |root|
      FileUtils.mkdir_p(File.join(root, "db"))
      File.write(File.join(root, "db", "schema.rb"), schema)

      unless migrations.empty?
        FileUtils.mkdir_p(File.join(root, "db", "migrate"))
        migrations.each { |name, body| File.write(File.join(root, "db", "migrate", name), body) }
      end

      Shipshape::TableShapes.new(root: root).call.to_h { |t| [t.name, t] }
    end
  end
end
