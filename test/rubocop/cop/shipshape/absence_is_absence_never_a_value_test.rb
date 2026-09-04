# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `null_option` answer nil reddens every offence test; making
# `promotions_in` answer `[]` reddens the promotion test, which is the clause that makes the rule
# workable on a populated table; making `reversing?` answer false reddens the `down` and
# `remove_column` tests; making `owned?` answer true unconditionally reddens the unowned-table
# test; making `polymorphic?` answer false unconditionally reddens the polymorphic tests.
class AbsenceIsAbsenceNeverAValueTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::AbsenceIsAbsenceNeverAValue

  PATH = "db/migrate/20260101000000_add_nickname_to_guests.rb"

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "record" => ["app/records/**/*_record.rb"] },
      "Matrix" => { "record" => [] },
      "BaseClasses" => { "record" => ["ApplicationRecord", "ActiveRecord::Base"] },
    },
  }.freeze

  # `guests` and `bookings` are claimed explicitly, which is the common case and the one every
  # pre-existing offence test below relies on.
  RECORDS = {
    "app/records/guest_record.rb" =>
      "class GuestRecord < ApplicationRecord\n  self.table_name = \"guests\"\nend\n",
    "app/records/booking_record.rb" =>
      "class BookingRecord < ApplicationRecord\n  self.table_name = \"bookings\"\nend\n",
  }.freeze

  def test_a_nullable_column_in_a_table_body_is_an_offence
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          create_table :guests do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`guests.nickname` is nullable"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          add_column :guests, :nickname, :string, null: true
        end
      end
    RUBY

    assert_includes message, 'WHY: A null is not "off", not "inherit"'
    assert_includes message, "INSTEAD:"
    assert_includes message, "add_index :person_nicknames, :person_id, unique: true"
  end

  def test_a_not_null_column_is_the_shape
    assert_empty check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          create_table :guests do |t|
            t.string :nickname, null: false
          end
        end
      end
    RUBY
  end

  # The clause that makes the law workable on a populated table.
  def test_a_column_promoted_in_the_same_method_passes
    assert_empty check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def up
          add_column :guests, :nickname, :string, null: true
          GuestRecord.update_all(nickname: "")
          change_column_null :guests, :nickname, false
        end
      end
    RUBY
  end

  def test_a_different_column_promoted_does_not_excuse_this_one
    assert_equal 1, check(<<~RUBY).length
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def up
          add_column :guests, :nickname, :string, null: true
          change_column_null :guests, :other, false
        end
      end
    RUBY
  end

  def test_the_reverse_direction_is_exempt
    assert_empty check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def down
          change_column_null :guests, :nickname, true
        end
      end
    RUBY
  end

  def test_a_reference_is_resolved_to_the_column_it_creates
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          add_reference :bookings, :supplier, null: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`bookings.supplier_id` is nullable",
      "A reference creates `<name>_id`, not the association name — the message must " \
      "name the column that actually exists."
  end

  # `polymorphic: true` creates `_id` AND `_type`, both nullable from this one option — naming
  # only `_id` would steer the fix toward half a table.
  def test_a_polymorphic_reference_names_both_columns_it_creates
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          add_reference :bookings, :supplier, polymorphic: true, null: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`bookings.supplier_id` and `bookings.supplier_type` are nullable"
  end

  def test_a_polymorphic_reference_that_says_nothing_names_both_columns
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          add_reference :bookings, :supplier, polymorphic: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message,
      "`bookings.supplier_id` and `bookings.supplier_type` say nothing about `null:`"
  end

  # `polymorphic: false` (the default) still creates one column, not two.
  def test_a_non_polymorphic_reference_names_only_its_id_column
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          add_reference :bookings, :supplier, polymorphic: false, null: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`bookings.supplier_id` is nullable"
    refute_includes found.first.message, "supplier_type"
  end

  # One column promoted and not the other is not both fixed — only the one still nullable
  # is named, so the message never claims more than it read.
  def test_a_polymorphic_reference_with_only_one_column_promoted_names_only_that_one
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def up
          add_reference :bookings, :supplier, polymorphic: true, null: true
          change_column_null :bookings, :supplier_type, false
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`bookings.supplier_id` is nullable"
    refute_includes found.first.message, "supplier_type"
  end

  def test_a_column_that_says_nothing_is_nullable
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          create_table :guests do |t|
            t.string :nickname
            t.integer :age
          end
          add_column :guests, :note, :string
        end
      end
    RUBY

    assert_equal 3, found.length
    assert_includes found.first.message, "says nothing about `null:`, which means nullable",
      "The case the cop missed entirely at first: a column with no `null:` is nullable, and that is how nearly every nullable column arrives."
  end

  def test_declarations_that_are_not_columns_are_left_alone
    assert_empty check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          create_table :guests do |t|
            t.timestamps
            t.index :reference
          end
        end
      end
    RUBY
  end

  def test_change_column_names_the_column_not_the_table
    found = check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          change_column :guests, :state, :string, null: true
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`guests.state` is nullable"
  end

  def test_change_column_is_promoted_by_the_same_method
    assert_empty check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def up
          change_column :guests, :state, :string, null: true
          change_column_null :guests, :state, false
        end
      end
    RUBY
  end

  # A promotion built in a loop cannot be read, so the addition beside it is not reported
  # either. A guard that cannot see the promotion must not fail the addition.
  def test_a_non_literal_column_is_skipped_rather_than_crashed_on
    assert_empty check(<<~RUBY)
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        COLUMNS = %i[nickname alias_name].freeze

        def up
          COLUMNS.each do |column|
            add_column :guests, column, :string, null: true
            GuestRecord.update_all(column => "")
            change_column_null :guests, column, false
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
      class AddNicknameToGuests < ActiveRecord::Migration[7.0]
        def change
          add_column :guests, :nickname, :string, NULL => false
        end
      end
    RUBY
  end

  # The clause this rename added: a table nobody has modelled yet does not fire, so an
  # adopter with hundreds of legacy tables is not pushed to bury the null in a satellite join
  # just to quiet a table it has not reached.
  def test_a_table_with_no_owning_record_is_silent
    assert_empty offences(<<~RUBY, cop_class: COP, path: PATH, files: RECORDS, other_cops: LAYOUT)
      class AddNicknameToWidgets < ActiveRecord::Migration[7.0]
        def change
          create_table :widgets do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY
  end

  # Rails' own default: no `self.table_name` at all still claims the table its class name
  # pluralises to.
  def test_a_record_with_no_explicit_table_name_still_claims_its_default
    files = RECORDS.merge("app/records/widget_record.rb" => "class Widget < ApplicationRecord\nend\n")

    found = offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToWidgets < ActiveRecord::Migration[7.0]
        def change
          create_table :widgets do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`widgets.nickname` is nullable"
  end

  # A subclass of an application record is not itself the base Rails would derive a table
  # name from, so it claims nothing on its own — the guard's disclosed blind spot, not a crash.
  def test_an_sti_subclass_does_not_claim_a_table_of_its_own
    files = RECORDS.merge(
      "app/records/user_record.rb" => "class User < ApplicationRecord\n  self.table_name = \"users\"\nend\n",
      "app/records/admin_user_record.rb" => "class AdminUser < User\nend\n",
    )

    assert_empty offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToAdminUsers < ActiveRecord::Migration[7.0]
        def change
          create_table :admin_users do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY
  end

  # `Gateway` used to pluralise to `gatewaies`; a vowel before the `y` just takes an `s`.
  def test_a_vowel_y_class_name_claims_its_regular_plural
    files = RECORDS.merge("app/records/gateway_record.rb" => "class Gateway < ApplicationRecord\nend\n")

    found = offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToGateways < ActiveRecord::Migration[7.0]
        def change
          create_table :gateways do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`gateways.nickname` is nullable"
  end

  # `BillingSettings` used to pluralise to `billing_settingses`; a class name already plural
  # is left alone, the same as Rails' own fallback for a bare trailing `s`.
  def test_an_already_plural_class_name_claims_its_own_table
    files = RECORDS.merge(
      "app/records/billing_settings_record.rb" => "class BillingSettings < ApplicationRecord\nend\n",
    )

    found = offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToBillingSettings < ActiveRecord::Migration[7.0]
        def change
          create_table :billing_settings do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`billing_settings.nickname` is nullable"
  end

  # A namespaced record written the compact way claims its module's own prefix, wherever
  # under `app/` or `lib/` that module happens to declare it.
  def test_a_namespaced_record_claims_its_module_table_name_prefix
    files = RECORDS.merge(
      "app/records/reseller_record.rb" =>
        "class ChannelManagement::Reseller < ApplicationRecord\nend\n",
      "app/channel_management.rb" =>
        "module ChannelManagement\n  def self.table_name_prefix\n    \"channel_management_\"\n  end\nend\n",
    )

    found = offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToChannelManagementResellers < ActiveRecord::Migration[7.0]
        def change
          create_table :channel_management_resellers do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`channel_management_resellers.nickname` is nullable"
  end

  # Nested — `module Foo; class Bar < ApplicationRecord; end; end` — claims its module's
  # prefix too: the class line alone never names `GetYourGuide`.
  def test_a_namespaced_record_written_the_nested_way_claims_its_module_table_name_prefix
    files = RECORDS.merge(
      "app/records/notification_record.rb" =>
        "module GetYourGuide\n  class Notification < ApplicationRecord\n  end\nend\n",
      "app/get_your_guide.rb" =>
        "module GetYourGuide\n  def self.table_name_prefix\n    \"get_your_guide_\"\n  end\nend\n",
    )

    found = offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToGetYourGuideNotifications < ActiveRecord::Migration[7.0]
        def change
          create_table :get_your_guide_notifications do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`get_your_guide_notifications.nickname` is nullable"
  end

  # Without the prefix, the demodulised guess would claim the wrong table (`resellers`), so
  # the real table stays silent — this is the defect being fixed, pinned as a regression test.
  def test_a_namespaced_record_does_not_claim_the_demodulised_table
    files = RECORDS.merge(
      "app/records/reseller_record.rb" =>
        "class ChannelManagement::Reseller < ApplicationRecord\nend\n",
      "app/channel_management.rb" =>
        "module ChannelManagement\n  def self.table_name_prefix\n    \"channel_management_\"\n  end\nend\n",
    )

    assert_empty offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToResellers < ActiveRecord::Migration[7.0]
        def change
          create_table :resellers do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY
  end

  # Disclosed, not guessed at: a file with two top-level modules leaves no static way to say
  # which one owns the prefix, so neither is claimed and the table stays silent.
  def test_a_prefix_file_declaring_two_modules_is_not_trusted
    files = RECORDS.merge(
      "app/records/reseller_record.rb" =>
        "class ChannelManagement::Reseller < ApplicationRecord\nend\n",
      "app/channel_management.rb" =>
        "module ChannelManagement\n  def self.table_name_prefix\n    \"channel_management_\"\n  end\nend\n\n" \
        "module SomethingElse\nend\n",
    )

    assert_empty offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToChannelManagementResellers < ActiveRecord::Migration[7.0]
        def change
          create_table :channel_management_resellers do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY
  end

  # `self.table_name = :services_suburbs` is a bare symbol, not a quoted string, and it is
  # exactly as literal — regression for a real table this missed until measured.
  def test_a_symbol_table_name_assignment_claims_its_table
    files = RECORDS.merge(
      "app/records/service_suburb_record.rb" =>
        "class ServiceSuburb < ApplicationRecord\n  self.table_name = :services_suburbs\nend\n",
    )

    found = offences(<<~RUBY, cop_class: COP, path: PATH, files: files, other_cops: LAYOUT)
      class AddNicknameToServicesSuburbs < ActiveRecord::Migration[7.0]
        def change
          create_table :services_suburbs do |t|
            t.string :nickname, null: true
          end
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`services_suburbs.nickname` is nullable"
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH, files: RECORDS, other_cops: LAYOUT)
  end
end
