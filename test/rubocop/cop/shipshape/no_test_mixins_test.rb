# frozen_string_literal: true

require "test_helper"

# Watched to fail: dropping the `node.receiver` guard reddens the receiver test by flagging a
# false positive; removing `self_type?` from `allowed?` reddens the `extend self` test; taking
# `Comparable` off LANGUAGE_MODULES reddens the language-module test.
class NoTestMixinsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoTestMixins

  def test_including_a_module_into_a_test_is_an_offence
    found = check("class FooTest < TestCase\n  include SignsInAsAdmin\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "puts behaviour on this test from a file"
  end

  def test_extend_and_prepend_are_the_same_offence
    %w[extend prepend].each do |mixer|
      found = check("class FooTest < TestCase\n  #{mixer} SharedSetup\nend\n")

      assert_equal 1, found.length, mixer
    end
  end

  def test_the_offence_names_the_one_base_class
    message = check("include Paying\n").first.message

    assert_includes message, "WHY:"
    assert_includes message, "the one base class every test in the suite already inherits"
    assert_includes message, "class TestCase < ActiveSupport::TestCase"
  end

  def test_a_language_module_is_not_an_offence
    assert_empty check("class FooTest < TestCase\n  include Comparable\nend\n")
  end

  def test_extend_self_is_not_an_offence
    assert_empty check("module SharedSetup\n  extend self\nend\n")
  end

  def test_a_receiver_is_a_different_class_being_reopened_not_this_one
    assert_empty check("SomeClass.include(Paying)\n")
  end

  def test_a_bare_call_with_no_arguments_is_somebody_elses_method
    assert_empty check("extend\n")
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: "test/app/domain/sales/confirm_booking_test.rb")
  end
end
