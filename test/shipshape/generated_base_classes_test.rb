# frozen_string_literal: true

require "test_helper"
require "shipshape/install"

# The installer's own test proves the files are written and compile. This one loads them
# and exercises the contracts, because "it parses" is not "it holds" — a base class that
# accepted any return value would compile perfectly and enforce nothing.
#
# ActiveRecord is not here, so the two templates that open a transaction are given a stand
# in that yields. That is honest: what is under test is the Result contract, not Rails.
class GeneratedBaseClassesTest < Minitest::Test
  def self.load_generated_once
    root = Dir.mktmpdir("shipshape-generated")
    Shipshape::Install.new(root: root).call

    stub_active_record
    Shipshape::Install::FILES.each { |name| require File.join(root, "app/shipshape/#{name}.rb") }
  end

  def self.stub_active_record
    return if defined?(::ActiveRecord)

    base = Class.new do
      def self.transaction
        yield
      end
    end
    Object.const_set(:ActiveRecord, Module.new)
    ::ActiveRecord.const_set(:Base, base)
  end

  load_generated_once

  class Charge < Command
    def initialize(amount:)
      @amount = typed(amount, Integer)
    end

    def call
      @amount.positive? ? success(@amount) : failure(:not_positive)
    end
  end

  class Misbehaving < Command
    def call
      "a bare string"
    end
  end

  class Place < Entity
    def initialize(code:)
      @code = typed(code, String)
    end
  end

  class ListPlaces < Query
    def call
      [Place.new(code: "ZA")]
    end
  end

  class LeakyQuery < Query
    def call
      [{ code: "ZA" }]
    end
  end

  def test_a_command_answers_with_a_result
    result = Charge.call(amount: 5)

    assert_predicate result, :success?
    assert_equal 5, result.value
    assert_nil result.error
  end

  def test_an_expected_failure_comes_back_as_a_value
    result = Charge.call(amount: 0)

    refute_predicate result, :success?
    assert_equal :not_positive, result.error
  end

  # The contract is enforced at the class method, so a subclass cannot teach its callers a
  # second shape.
  def test_a_command_that_answers_with_anything_else_stops_the_run
    error = assert_raises(TypeError) { Misbehaving.call }

    assert_includes error.message, "must answer with a Result"
  end

  def test_arguments_are_asserted_at_construction
    assert_raises(ArgumentError) { Charge.call(amount: "5") }
  end

  def test_a_query_answers_with_entities_and_no_envelope
    answer = ListPlaces.call

    assert_equal [Place.new(code: "ZA")], answer
  end

  # Whatever the old code returned, the door decides the shape. A query leaking hashes is
  # the leak this check exists to stop.
  def test_a_query_that_answers_with_anything_else_stops_the_run
    error = assert_raises(TypeError) { LeakyQuery.call }

    assert_includes error.message, "must answer with entities"
  end

  def test_an_empty_answer_is_an_answer
    empty = Class.new(Query) { def call; []; end }

    assert_empty empty.call
  end

  # Value semantics without a macro: two entities of a class holding the same values are
  # the same entity, so they compare, deduplicate and assert equal.
  def test_entities_compare_by_value
    assert_equal Place.new(code: "ZA"), Place.new(code: "ZA")
    refute_equal Place.new(code: "ZA"), Place.new(code: "GB")
    assert_equal 1, [Place.new(code: "ZA"), Place.new(code: "ZA")].uniq.length
  end

  def test_an_error_code_is_a_name_not_a_sentence
    assert_raises(ArgumentError) { Result.failure("something went wrong") }
  end

  def test_boolean_is_a_name_and_reopens_nothing
    refute_includes true.class.ancestors, Boolean
    assert_equal "Boolean", Boolean.to_s
  end
end
