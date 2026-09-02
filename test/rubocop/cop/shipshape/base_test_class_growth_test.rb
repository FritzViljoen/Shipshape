# frozen_string_literal: true

require "test_helper"

# Watched to fail: dropping `defs_type?` from `method?` reddens the class-method test;
# removing `LIFECYCLE` reddens the `setup` test. The `Exclude` for leaf tests is proven by
# `bundle exec exe/shipshape canaries`, not here — `CopRunner#offences` never applies one.
class BaseTestClassGrowthTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::BaseTestClassGrowth

  def test_a_method_on_a_base_class_is_a_definition
    found = check(<<~RUBY)
      class TestCase < ActiveSupport::TestCase
        def sign_in_as(actor)
          @actor = actor
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "This base test class holds one more definition"
  end

  def test_every_definition_kind_is_counted
    found = check(<<~RUBY)
      class TestCase < ActiveSupport::TestCase
        def self.helper; end

        NAME = "x"

        attr_reader :actor

        setup do
          @actor = nil
        end
      end
    RUBY

    assert_equal 4, found.length
  end

  def test_an_empty_base_class_holds_no_definitions
    assert_empty check("class TestCase < ActiveSupport::TestCase\nend\n")
  end

  private

  def check(source, path: "test/support/admin_test_case.rb")
    offences(source, cop_class: COP, path: path)
  end
end
