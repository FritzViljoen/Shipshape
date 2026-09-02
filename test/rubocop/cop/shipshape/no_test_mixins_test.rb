# frozen_string_literal: true

require "test_helper"

# Watched to fail: dropping `node.receiver` reddens the receiver test; dropping `self_type?`
# reddens the `extend self` test; an exact-join-only `Kinds#under_roots` reddens the support tests.
class NoTestMixinsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoTestMixins

  # This cop's own `Include` in `config/default.yml`, not a second, drifting copy of it.
  INCLUDE = %w[test/**/*.rb spec/**/*.rb **/test/**/*.rb **/spec/**/*.rb].freeze

  def test_including_a_module_into_a_test_is_an_offence
    found = check("class FooTest < TestCase\n  include SignsInAsAdmin\nend\n",
                   files: { "test/signs_in_as_admin.rb" => "module SignsInAsAdmin\nend\n" })

    assert_equal 1, found.length
    assert_includes found.first.message, "puts behaviour on this test from a file"
  end

  # Exercises constant resolution, unlike every case above, which reaches for `extend self`.
  def test_a_module_in_the_support_directory_is_an_offence
    found = check("class FooTest < TestCase\n  include SignsInAsAdmin\nend\n",
                   files: { "test/support/signs_in_as_admin.rb" => "module SignsInAsAdmin\nend\n" })

    assert_equal 1, found.length
  end

  def test_a_module_in_the_spec_support_directory_is_an_offence
    found = check("class FooTest < TestCase\n  include SignsInAsAdmin\nend\n",
                   files: { "spec/support/signs_in_as_admin.rb" => "module SignsInAsAdmin\nend\n" })

    assert_equal 1, found.length
  end

  def test_extend_and_prepend_are_the_same_offence
    %w[extend prepend].each do |mixer|
      found = check("class FooTest < TestCase\n  #{mixer} SharedSetup\nend\n",
                     files: { "test/shared_setup.rb" => "module SharedSetup\nend\n" })

      assert_equal 1, found.length, mixer
    end
  end

  def test_the_offence_names_the_one_base_class
    message = check("include Paying\n",
                     files: { "test/paying.rb" => "module Paying\nend\n" }).first.message

    assert_includes message, "WHY:"
    assert_includes message, "the one base class every test in the suite already inherits"
    assert_includes message, "class TestCase < ActiveSupport::TestCase"
  end

  def test_a_language_module_is_not_an_offence
    assert_empty check("class FooTest < TestCase\n  include Comparable\nend\n")
  end

  def test_extend_self_is_an_offence
    found = check("module SharedSetup\n  extend self\nend\n", path: "test/shared_setup.rb")

    assert_equal 1, found.length
  end

  # None of these resolve to a file in this repository's own test tree.
  def test_a_stock_test_helper_draws_no_offence
    found = check(<<~RUBY, path: "test/test_helper.rb")
      class ActiveSupport::TestCase
        include Devise::Test::IntegrationHelpers
        include Capybara::DSL
        include WebMock::API
        include FactoryBot::Syntax::Methods
        extend Minitest::Spec::DSL
        include Rails.application.routes.url_helpers
      end
    RUBY

    assert_empty found
  end

  def test_a_receiver_is_a_different_class_being_reopened_not_this_one
    assert_empty check("SomeClass.include(Paying)\n")
  end

  def test_a_bare_call_with_no_arguments_is_somebody_elses_method
    assert_empty check("extend\n")
  end

  private

  def check(source, path: "test/app/domain/sales/confirm_booking_test.rb", files: {})
    offences(source, cop_class: COP, cop_config: { "Include" => INCLUDE }, path: path, files: files)
  end
end
