# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `typed` return its value unconditionally reddens every raising
# test here. A guard nobody has seen fail reads as coverage.
class TypedArgumentsTest < Minitest::Test
  # A stand-in caller, written the way the law asks: a hand-written initializer, one guard
  # per keyword, no macro.
  class Subject
    include Shipshape::TypedArguments

    attr_reader :name, :count, :tags, :labels

    def initialize(name:, count:, tags:, labels:)
      @name = typed(name, String)
      @count = typed(count, Integer, allow_nil: true)
      @tags = typed_array(tags, String)
      @labels = typed_hash(labels, String, Integer)
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

  # A Hash with the right keys and the wrong values is the commoner mistake, and the one a
  # bare Hash check misses.
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

  # The guard is private, so it cannot be reached from outside the object that declared
  # its own arguments — the boundary is the constructor, not a utility anyone may call.
  def test_the_guard_is_private
    refute_respond_to Subject.new(name: "x", count: 1, tags: [], labels: {}), :typed
  end
end
