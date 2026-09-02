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

  # The back door the reviewer built: three definitions with no bare `def` at the class body's
  # top level at all.
  def test_define_method_alias_method_and_delegate_are_all_definitions
    found = check(<<~RUBY)
      class AdminTestCase < ActiveSupport::TestCase
        %i[admin guest owner].each { |role| define_method("sign_in_as_\#{role}") { role } }

        if ENV["FAST"]
          def travel_to(time); end
        end

        class << self
          def helper_one; end
          def helper_two; end
        end

        alias_method :old_name, :new_name

        delegate :time_zone, to: :actor
      end
    RUBY

    assert_equal 6, found.length
  end

  def test_a_module_holds_definitions_the_same_way_a_class_does
    found = check(<<~RUBY, path: "test/support/shared_setup.rb")
      module SharedSetup
        extend self

        def a_confirmed_booking(**args)
          BookingRecord.create!(**args, state: "confirmed")
        end
      end
    RUBY

    assert_equal 1, found.length, "extend self is not itself a definition; the method it shares is"
  end

  def test_a_mailer_preview_is_not_a_base_test_class
    assert_empty check(<<~RUBY, path: "test/mailers/previews/user_mailer_preview.rb")
      class UserMailerPreview < ActionMailer::Preview
        def welcome
          UserMailer.welcome
        end
      end
    RUBY
  end

  def test_a_dummy_app_model_is_not_a_base_test_class
    assert_empty check(<<~RUBY, path: "test/dummy/app/models/user.rb")
      class User < ApplicationRecord
        def full_name
          "\#{first_name} \#{last_name}"
        end
      end
    RUBY
  end

  def test_an_admin_test_case_in_a_support_file_is_still_caught
    found = check(<<~RUBY, path: "test/support/admin_test_case.rb")
      class AdminTestCase < ActiveSupport::TestCase
        def sign_in_as_admin; end
      end
    RUBY

    assert_equal 1, found.length
  end

  # `BaseTestClassLines` reads sizes back from this same investigation - a qualifying class
  # records its own span, not a second reader's re-walk of the file.
  def test_a_qualifying_class_records_its_own_span
    COP.reset_spans!
    check(<<~RUBY)
      class TestCase < ActiveSupport::TestCase
        def sign_in_as(actor)
          @actor = actor
        end
      end
    RUBY

    assert_equal [5], COP.merged_sizes.values
  end

  def test_a_qualifying_module_records_its_own_span
    COP.reset_spans!
    check(<<~RUBY, path: "test/support/shared_setup.rb")
      module SharedSetup
        extend self

        def a_confirmed_booking(**args)
          BookingRecord.create!(**args, state: "confirmed")
        end
      end
    RUBY

    assert_equal [7], COP.merged_sizes.values
  end

  def test_a_non_qualifying_class_records_no_span
    COP.reset_spans!
    check(<<~RUBY, path: "test/mailers/previews/user_mailer_preview.rb")
      class UserMailerPreview < ActionMailer::Preview
        def welcome
          UserMailer.welcome
        end
      end
    RUBY

    assert_empty COP.spans
  end

  # A module wrapping the class it declares would otherwise count the same lines twice.
  def test_a_module_wrapping_a_qualifying_class_merges_into_one_span
    COP.reset_spans!
    check(<<~RUBY, path: "test/support/wrapped_test_case.rb")
      module Support
        class WrappedTestCase < ActiveSupport::TestCase
          def sign_in_as_admin; end
        end
      end
    RUBY

    assert_equal [5], COP.merged_sizes.values
  end

  private

  def check(source, path: "test/support/admin_test_case.rb")
    offences(source, cop_class: COP, path: path)
  end
end
