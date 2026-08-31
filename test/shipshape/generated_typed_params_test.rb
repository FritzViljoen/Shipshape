# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "active_support/all"
require "bigdecimal"

# The seam, exercised rather than compiled. Every case here is one an unparsed parameter
# would have got wrong quietly — which is the whole reason the seam exists.
#
# Watched to fail: neutering `refuse_conflicting_zone` reddens the disagreeing-offset case.
#
# And one guard was watched to fail and DID NOT: a literal `false` short-circuit copied
# from an earlier version turned out to be dead, because `parsed_param` tests nil-or-empty
# rather than `blank?`. It was deleted rather than kept as decoration — a line no test can
# redden is not a guard, and leaving it in would have read as protection.
class GeneratedTypedParamsTest < Minitest::Test
  root = Dir.mktmpdir("shipshape-params")
  Shipshape::Install.new(root: root).call
  require File.join(root, "app/shipshape/typed_params.rb")

  # A controller, minus Rails. `rescue_from` is absent, so BadParam surfaces as itself and
  # the test asserts on the refusal rather than on a redirect.
  class Action
    include TypedParams

    def initialize(params)
      @params = params
    end

    attr_reader :params

    public :integer_param, :integer_param!, :decimal_param, :boolean_param, :boolean_param!,
           :text_param, :text_param!, :enum_param, :enum_param!, :date_param, :time_param,
           :time_param!
  end

  ZONE = "Africa/Johannesburg"

  def test_an_integer_is_parsed_not_coerced
    assert_equal 12, action(id: "12").integer_param(:id)
  end

  # `"1abc".to_i` is 1, and `find` on it serves record 1 while nothing anywhere fails.
  def test_a_number_with_rubbish_after_it_is_not_a_number
    assert_nil action(id: "1abc").integer_param(:id),
      "This is the single trap the seam exists to close."
    assert_raises(TypedParams::BadParam) { action(id: "1abc").integer_param!(:id) }
  end

  def test_a_missing_value_answers_with_the_default
    assert_equal 1, action({}).integer_param(:page, default: 1)
    assert_raises(TypedParams::BadParam) { action({}).integer_param!(:page) }
  end

  def test_a_decimal_is_a_bigdecimal_and_never_infinite
    assert_equal BigDecimal("1.05"), action(amount: "1.05").decimal_param(:amount)
    assert_nil action(amount: "Infinity").decimal_param(:amount)
  end

  def test_a_genuine_false_is_not_the_default
    assert_equal false, action(tie: "false").boolean_param(:tie, default: true)
    assert_equal false, action(tie: false).boolean_param(:tie, default: true)
    assert_equal true, action(tie: "1").boolean_param(:tie),
      "`false.blank?` is true, so a genuine false read after a blank guard comes back as the default — the parameter says no and the application hears nothing."
  end

  def test_a_boolean_that_is_neither_bounces
    assert_raises(TypedParams::BadParam) { action(tie: "yes").boolean_param!(:tie) }
  end

  # The default is "no search", so falling back to it would answer an over-long search
  def test_an_over_long_search_bounces_from_both_forms
    long = "x" * 201

    assert_raises(TypedParams::BadParam) { action(q: long).text_param(:q) }
    assert_raises(TypedParams::BadParam) { action(q: long).text_param!(:q) }
    assert_equal "ok", action(q: "  ok  ").text_param(:q),
      "with the whole list — the broadest possible answer to a question nobody asked."
  end

  def test_a_value_outside_a_closed_set_is_refused
    assert_equal "name", action(sort: "name").enum_param(:sort, %w[name age])
    assert_nil action(sort: "; DROP").enum_param(:sort, %w[name age])
    assert_raises(TypedParams::BadParam) { action(sort: "; DROP").enum_param!(:sort, %w[name age]) }
  end

  def test_a_time_is_read_in_the_zone_the_action_named
    at = action(at: "2026-03-03 18:00").time_param(:at, time_zone: ZONE)

    assert_equal 2, at.utc_offset / 3600
    assert_equal 18, at.hour
  end

  # `2026-03-03T18:00+05:00` read in Johannesburg states two answers. Neither is taken.
  def test_a_stated_offset_disagreeing_with_the_zone_bounces
    assert_raises(TypedParams::BadParam) do
      action(at: "2026-03-03T18:00:00+05:00").time_param(:at, time_zone: ZONE)
    end
  end

  def test_a_stated_offset_agreeing_with_the_zone_is_fine
    at = action(at: "2026-03-03T18:00:00+02:00").time_param(:at, time_zone: ZONE)

    assert_equal 18, at.hour
  end

  # There is no ambient zone to fall back on: the keyword is required, so an action that
  # forgot it fails at the call site rather than silently reading the server's.
  def test_the_zone_is_required
    assert_raises(ArgumentError) { action(at: "2026-03-03").date_param(:at) }
  end

  def test_a_date_carries_no_zone
    on = action(on: "2026-03-03").date_param(:on, time_zone: ZONE)

    assert_instance_of Date, on
    assert_equal 3, on.day
  end

  private

  def action(params)
    Action.new(params)
  end
end
