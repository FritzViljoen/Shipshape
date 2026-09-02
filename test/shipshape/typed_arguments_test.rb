# frozen_string_literal: true

require "test_helper"
require "active_support/time"

# Watched to fail: making `typed` return its value unconditionally reddens every raising test here,
# and making `matches?` answer true for Boolean reddens the three Boolean cases. Restoring each
# returns them to green. A guard nobody has seen fail reads as coverage.
class TypedArgumentsTest < Minitest::Test
  class Subject
    include Shipshape::TypedArguments

    attr_reader :name, :count, :tags, :labels, :tie

    def initialize(name:, count:, tags:, labels:, tie: false)
      @name = typed(name, String)
      @count = typed(count, Integer, allow_nil: true)
      @tags = typed_array(tags, String)
      @labels = typed_hash(labels, String, Integer)
      @tie = typed(tie, Shipshape::Boolean)
    end
  end

  def test_it_passes_values_of_the_declared_type_through
    subject = Subject.new(name: "x", count: 1, tags: ["a"], labels: { "a" => 1 })

    assert_equal "x", subject.name
    assert_equal 1, subject.count
    assert_equal ["a"], subject.tags
    assert_equal({ "a" => 1 }, subject.labels)
  end

  def test_it_asserts_rather_than_coercing
    error = assert_raises(ArgumentError) { Subject.new(name: 1, count: 1, tags: [], labels: {}) }

    assert_includes error.message, "expected String, got Integer"
  end

  def test_nil_is_refused_unless_the_keyword_allows_it
    assert_raises(ArgumentError) { Subject.new(name: nil, count: 1, tags: [], labels: {}) }
    assert_nil Subject.new(name: "x", count: nil, tags: [], labels: {}).count
  end

  def test_an_array_is_checked_element_by_element
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: ["a", 2], labels: {}) }
  end

  def test_a_hash_is_checked_on_both_sides
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: { "a" => "1" }) }
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: { a: 1 }) }
  end

  def test_an_empty_array_may_be_refused_where_a_caller_asks
    subject = Class.new do
      include Shipshape::TypedArguments

      def initialize(items)
        @items = typed_array(items, String, allow_empty: false)
      end
    end

    assert_raises(ArgumentError) { subject.new([]) }
  end

  def test_boolean_accepts_both_of_them_and_nothing_else
    assert_equal true, Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: true).tie
    assert_equal false, Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: false).tie

    error = assert_raises(ArgumentError) do
      Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: "true")
    end

    assert_includes error.message, "expected Boolean, got String"
  end

  # "Not supplied" and "supplied as false" are different facts; a keyword that may be absent
  # says so.
  def test_nil_is_not_false
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: nil) }
  end

  def test_a_truthy_value_is_not_a_boolean
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: 1) }
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: Object.new) }
  end

  def test_boolean_does_not_reopen_the_core_classes
    refute_includes true.class.ancestors, Shipshape::Boolean
    refute_includes false.class.ancestors, Shipshape::Boolean,
      "A gem that reopened TrueClass and FalseClass would change two objects nobody owns, from a dev dependency, invisibly. Boolean is a name and is included nowhere."
  end

  # Private, so the boundary is the constructor rather than a utility anyone may call.
  def test_the_guard_is_private
    refute_respond_to Subject.new(name: "x", count: 1, tags: [], labels: {}), :typed
  end
end

# `a-time-names-its-zone`: `Time`/`DateTime` require a zoned value; `Date` refuses a `DateTime`.
# Watched to fail: reverting `matches?` to plain `is_a?` reddens every refusal below.
class TypedArgumentsTimeZoneTest < Minitest::Test
  class Moment
    include Shipshape::TypedArguments

    attr_reader :at, :on

    def initialize(at:, on:)
      @at = typed(at, Time)
      @on = typed(on, Date)
    end
  end

  ZONED = ActiveSupport::TimeZone["UTC"].now

  def test_a_naive_time_is_refused_where_a_moment_is_declared
    error = assert_raises(ArgumentError) { Moment.new(at: Time.now, on: Date.today) }

    assert_includes error.message, "expected a zoned Time"
    assert_includes error.message, "with no zone"
  end

  def test_a_naive_datetime_is_refused_the_same_way
    subject = Class.new do
      include Shipshape::TypedArguments

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
      include Shipshape::TypedArguments

      def initialize(at:)
        @at = typed(at, ActiveSupport::TimeWithZone)
      end
    end

    subject.new(at: ZONED)
    assert_raises(ArgumentError) { subject.new(at: Time.now) }
  end

  # The gem takes no runtime ActiveSupport dependency, so this spawns a bare subprocess: must
  # refuse the value rather than raise `NameError` on the bare constant reference.
  def test_without_activesupport_loaded_a_moment_never_matches_rather_than_raising
    script = <<~RUBY
      $LOAD_PATH.unshift(#{File.expand_path("../../lib", __dir__).inspect})
      require "shipshape/typed_arguments"

      class Probe
        include Shipshape::TypedArguments

        def initialize(at:)
          @at = typed(at, Time)
        end
      end

      begin
        Probe.new(at: Time.now)
        puts "PASSED-WRONGLY"
      rescue ArgumentError
        puts "REFUSED"
      rescue NameError => e
        puts "NAMEERROR: \#{e.message}"
      end
    RUBY

    output = IO.popen(["ruby", "-e", script], err: [:child, :out], &:read)

    assert_equal "REFUSED", output.strip
  end
end
