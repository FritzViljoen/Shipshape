# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "active_support/all"

# Installed into a Rails app, where ActiveSupport is guaranteed — unlike the gem's own copy
# (typed_arguments_test.rb). Watched to fail: reverting `matches?` reddens every refusal here.
class GeneratedTypedArgumentsTest < Minitest::Test
  root = Dir.mktmpdir("shipshape-typed-arguments")
  Shipshape::Install.new(root: root).call
  require File.join(root, "app/shipshape/boolean.rb")
  require File.join(root, "app/shipshape/holds_no_records.rb")
  require File.join(root, "app/shipshape/typed_arguments.rb")

  class Moment
    include TypedArguments

    attr_reader :at, :on

    def initialize(at:, on:)
      @at = typed(at, Time)
      @on = typed(on, Date)
    end
  end

  ZONED = ActiveSupport::TimeZone["UTC"].now

  def test_a_naive_time_is_refused_where_a_moment_is_declared
    assert_raises(ArgumentError) { Moment.new(at: Time.now, on: Date.today) }
  end

  def test_a_naive_datetime_is_refused_the_same_way
    subject = Class.new do
      include TypedArguments

      def initialize(at:)
        @at = typed(at, DateTime)
      end
    end

    assert_raises(ArgumentError) { subject.new(at: DateTime.now) }
  end

  def test_a_zoned_time_is_accepted_however_it_was_declared
    assert_equal ZONED, Moment.new(at: ZONED, on: Date.today).at
  end

  def test_a_calendar_date_is_accepted
    assert_equal Date.today, Moment.new(at: ZONED, on: Date.today).on
  end

  def test_a_datetime_is_refused_where_a_date_is_declared
    assert_raises(ArgumentError) { Moment.new(at: ZONED, on: DateTime.now) }
  end

  # The recommended spelling (the cop's own suggested fix): a moment is declared as the class
  # a zoned value actually is, and the guard treats it as any other declared type.
  def test_declaring_time_with_zone_directly_works_like_any_other_type
    subject = Class.new do
      include TypedArguments

      def initialize(at:)
        @at = typed(at, ActiveSupport::TimeWithZone)
      end
    end

    subject.new(at: ZONED)
    assert_raises(ArgumentError) { subject.new(at: Time.now) }
  end
end
