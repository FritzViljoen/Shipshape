# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `factory?` answer false reddens the `create`, `build` and library tests;
# making `fixtures?` answer false reddens the two fixture tests; dropping the symbol-argument test
# from `factory?` reddens the not-a-factory tests, which are the shape that would fail correct code
# — `create(record)` and `build(io)` are ordinary Ruby and appear in suites that have never seen
class NoTestFactoriesTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoTestFactories

  def test_a_bare_factory_call_is_an_offence
    found = check("booking = create(:booking, status: \"confirmed\")\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`create` builds domain state without going through an operation"
  end

  def test_the_offence_says_the_state_may_be_unreachable
    message = check("create(:booking)\n").first.message

    assert_includes message, "WHY:"
    assert_includes message, "a factory can produce a row the application cannot"
    assert_includes message, "asserts behaviour on fiction"
    assert_includes message, "CreateBooking.test_call(offer_id: offer.id).value"
  end

  def test_every_builder_in_the_dsl_is_matched
    %w[create create_list build build_list build_stubbed attributes_for].each do |builder|
      assert_equal 1, check("#{builder}(:booking)\n").length, builder
    end
  end

  def test_the_libraries_are_matched_by_name
    ["FactoryBot.create(:booking)", "FactoryGirl.build(:booking)", "Fabricate(:booking)"].each do |source|
      assert_equal 1, check("#{source}\n").length, source
    end
  end

  def test_fixtures_are_the_same_defect
    found = check("fixtures :all\n")

    assert_equal 1, found.length,
      "Fixtures are the same second construction, loaded earlier and shared by everything."
    assert_includes found.first.message, "Fixtures build domain state without going through an operation"
  end

  def test_the_fixture_offence_names_the_sharing
    message = check("fixtures :bookings, :offers\n").first.message

    assert_includes message, "every other test silently depends on"
  end

  # `create` and `build` are ordinary words, and a suite with no factory contains both.
  def test_create_on_a_value_is_not_a_factory
    assert_empty check(<<~RUBY)
      record = create(attributes)
      other = build(io_client)
      third = create_list(rows, 3)
    RUBY
  end

  def test_a_receiver_makes_it_somebody_elses_method
    assert_empty check("client.create(:booking)\nbuilder.build(:thing)\n")
  end

  def test_a_plain_lookup_is_not_a_factory
    assert_empty check(%(currency = Currency.find_by!(code: "ZAR")\n))
  end

  def test_building_state_through_operations_is_the_shape
    assert_empty check(<<~RUBY)
      booking = CreateBooking.test_call(offer_id: offer.id).value
      ConfirmBooking.test_call(booking_id: booking.id)
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: "test/app/domain/sales/cancel_booking_test.rb")
  end
end
