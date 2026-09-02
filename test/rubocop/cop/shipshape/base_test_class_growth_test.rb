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

  # The span travels as an offence - `BaseTestClassLines` reads it back from RuboCop's own
  # JSON, never from state held on this class. `record_span` is a no-op unless the reader
  # asks for it, so a plain `rubocop` run - this test's default, `RECORD_SPANS_ENV` unset -
  # emits none of it.
  def test_a_span_offence_is_not_recorded_unless_asked_for
    found = check(<<~RUBY)
      class TestCase < ActiveSupport::TestCase
        def sign_in_as(actor)
          @actor = actor
        end
      end
    RUBY

    assert_empty spans(found)
  end

  # `BaseTestClassLines` reads sizes back from this same investigation - a qualifying class
  # records its own span, not a second reader's re-walk of the file.
  def test_a_qualifying_class_records_its_own_span
    found = with_span_recording do
      check(<<~RUBY)
        class TestCase < ActiveSupport::TestCase
          def sign_in_as(actor)
            @actor = actor
          end
        end
      RUBY
    end

    assert_equal [1..5], spans(found)
  end

  def test_a_qualifying_module_records_its_own_span
    found = with_span_recording do
      check(<<~RUBY, path: "test/support/shared_setup.rb")
        module SharedSetup
          extend self

          def a_confirmed_booking(**args)
            BookingRecord.create!(**args, state: "confirmed")
          end
        end
      RUBY
    end

    assert_equal [1..7], spans(found)
  end

  def test_a_non_qualifying_class_records_no_span
    found = with_span_recording do
      check(<<~RUBY, path: "test/mailers/previews/user_mailer_preview.rb")
        class UserMailerPreview < ActionMailer::Preview
          def welcome
            UserMailer.welcome
          end
        end
      RUBY
    end

    assert_empty spans(found)
  end

  # A module wrapping the class it declares emits two overlapping span offences - merging
  # them into one size is `BaseTestClassLines`' job, over RuboCop's own JSON, not a second
  # copy of this classification.
  def test_a_module_wrapping_a_qualifying_class_records_both_spans
    found = with_span_recording do
      check(<<~RUBY, path: "test/support/wrapped_test_case.rb")
        module Support
          class WrappedTestCase < ActiveSupport::TestCase
            def sign_in_as_admin; end
          end
        end
      RUBY
    end

    assert_equal [1..5, 2..4], spans(found)
  end

  private

  def check(source, path: "test/support/admin_test_case.rb")
    offences(source, cop_class: COP, path: path)
  end

  # `RECORD_SPANS_ENV` is `BaseTestClassLines`' own signal to its subprocess - set and torn
  # down around one call here, never left on for a test that runs after this one.
  def with_span_recording
    was = ENV[COP::RECORD_SPANS_ENV]
    ENV[COP::RECORD_SPANS_ENV] = "1"
    yield
  ensure
    ENV[COP::RECORD_SPANS_ENV] = was
  end

  def spans(found)
    found.select { |offence| offence.message == COP::SPAN_MESSAGE }
         .map { |offence| offence.location.line..offence.location.last_line }
  end
end
