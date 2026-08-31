# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `on_resbody` return early reddens every offence test; making `only_logs?`
# answer false reddens the log tests; making `literal?` answer false reddens the literal test;
# making `answering_a_predicate?` answer true reddens the non-predicate boolean test; making it
# answer false reddens the predicate test.
class NoEmptyRescueTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoEmptyRescue

  PATH = "app/commands/charge_card.rb"

  def test_an_empty_rescue_is_an_offence
    found = check(<<~RUBY)
      def call
        @gateway.charge(@amount)
      rescue StandardError
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "This rescue is empty"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      def call
        @gateway.charge(@amount)
      rescue StandardError
      end
    RUBY

    assert_includes message, "WHY: The dangerous failure is not the unknown error"
    assert_includes message, "Yuan et al. (OSDI 2014)"
    assert_includes message, "INSTEAD:"
    assert_includes message, "failure(:supplier_rejected, detail: e.message)"
  end

  def test_a_rescue_that_only_logs_is_an_offence
    found = check(<<~RUBY)
      def call
        @gateway.charge(@amount)
      rescue StandardError => e
        Rails.logger.error(e)
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "This rescue only logs"
  end

  def test_a_rescue_that_only_returns_a_literal_is_an_offence
    found = check(<<~RUBY)
      def call
        @gateway.charge(@amount)
      rescue StandardError
        nil
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "only returns `nil`"
  end

  def test_a_rescue_that_answers_with_a_value_is_the_shape
    assert_empty check(<<~RUBY)
      def call
        success(@gateway.charge(@amount))
      rescue Supplier::Rejected => e
        failure(:supplier_rejected, detail: e.message)
      end
    RUBY
  end

  def test_logging_and_then_answering_is_the_shape
    assert_empty check(<<~RUBY)
      def call
        success(@gateway.charge(@amount))
      rescue Supplier::Rejected => e
        Rails.logger.error(e)
        failure(:supplier_rejected)
      end
    RUBY
  end

  def test_re_raising_is_the_shape
    assert_empty check(<<~RUBY)
      def call
        @gateway.charge(@amount)
      rescue StandardError
        raise Supplier::Unavailable
      end
    RUBY
  end

  # The one shape where a literal is the answer rather than a default: the question had
  # two outcomes and the failure produced one of them.
  def test_a_predicate_rescuing_to_a_boolean_is_answering
    assert_empty check(<<~RUBY)
      def repository?
        run("rev-parse", "--git-dir")
        true
      rescue Error
        false
      end
    RUBY
  end

  def test_a_non_predicate_rescuing_to_a_boolean_is_still_swallowing
    assert_equal 1, check(<<~RUBY).length
      def charge
        @gateway.charge(@amount)
      rescue Error
        false
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
