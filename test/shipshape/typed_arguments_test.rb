# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `typed` return its value unconditionally reddens every raising test here,
# and making `matches?` answer true for Boolean reddens the three Boolean cases. Restoring each
# returns them to green. A guard nobody has seen fail reads as coverage.
class TypedArgumentsTest < Minitest::Test
  # A stand-in caller, written the way the law asks: a hand-written initializer, one guard
  # per keyword, no macro.
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

  def test_boolean_accepts_both_of_them_and_nothing_else
    assert_equal true, Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: true).tie
    assert_equal false, Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: false).tie

    error = assert_raises(ArgumentError) do
      Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: "true")
    end

    assert_includes error.message, "expected Boolean, got String"
  end

  # "Not supplied" and "supplied as false" are different facts, and `absence-is-absence`
  # refuses to let one stand for the other. A keyword that may be absent says so.
  def test_nil_is_not_false
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: nil) }
  end

  # Truthiness is not a Boolean. Anything else accepted here would be a coercion, and this
  # guard asserts rather than coercing.
  def test_a_truthy_value_is_not_a_boolean
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: 1) }
    assert_raises(ArgumentError) { Subject.new(name: "x", count: 1, tags: [], labels: {}, tie: Object.new) }
  end

  def test_boolean_does_not_reopen_the_core_classes
    refute_includes true.class.ancestors, Shipshape::Boolean
    refute_includes false.class.ancestors, Shipshape::Boolean,
      "A gem that reopened TrueClass and FalseClass would change two objects nobody owns, from a dev dependency, invisibly. Boolean is a name and is included nowhere."
  end

  # The guard is private, so it cannot be reached from outside the object that declared
  # its own arguments — the boundary is the constructor, not a utility anyone may call.
  def test_the_guard_is_private
    refute_respond_to Subject.new(name: "x", count: 1, tags: [], labels: {}), :typed
  end
end
