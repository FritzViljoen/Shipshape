# frozen_string_literal: true

require "test_helper"
require "shipshape/base_test_class_lines"

# Every repository below carries a second Ruby file (turns `--parallel` on) and every
# measurement below runs twice over it (a warm cache on the second) - a lone file in a fresh
# `Dir.mktmpdir` is the one shape blind to either way this class used to measure `{}`.
class BaseTestClassLinesTest < Minitest::Test
  RUBOCOP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false
  YAML

  DISABLED_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/BaseTestClassGrowth:
      Enabled: false
  YAML

  # No `require:` at all - `BaseTestClassLines` supplies `--require shipshape` regardless.
  NO_REQUIRE_YML = <<~YAML
    AllCops:
      NewCops: disable
      SuggestExtensions: false
  YAML

  def test_a_base_test_classs_own_span_is_its_size
    in_repo(RUBOCOP_YML) do |root|
      write(root, "test/support/admin_test_case.rb", <<~RUBY)
        class AdminTestCase < ActiveSupport::TestCase
          def sign_in_as_admin; end
        end
      RUBY

      sizes = call(root)

      assert_equal 3, sizes.fetch("test/support/admin_test_case.rb")
    end
  end

  # The class's own span is measured, not the definitions `handle_body` recurses into.
  def test_a_comment_above_the_class_does_not_inflate_its_size
    in_repo(RUBOCOP_YML) do |root|
      write(root, "test/support/admin_test_case.rb", <<~RUBY)
        # three lines of preamble
        # that are not the class body
        # at all
        class AdminTestCase < ActiveSupport::TestCase
          def sign_in_as_admin; end
        end
      RUBY

      sizes = call(root)

      assert_equal 3, sizes.fetch("test/support/admin_test_case.rb")
    end
  end

  # A module wrapping the class it declares would otherwise count the same lines twice.
  def test_a_module_wrapping_a_qualifying_class_does_not_double_count
    in_repo(RUBOCOP_YML) do |root|
      write(root, "test/support/wrapped_test_case.rb", <<~RUBY)
        module Support
          class WrappedTestCase < ActiveSupport::TestCase
            def sign_in_as_admin; end
          end
        end
      RUBY

      sizes = call(root)

      assert_equal 5, sizes.fetch("test/support/wrapped_test_case.rb")
    end
  end

  # A base class holding zero definitions still has a span - what a golfed class must ratchet.
  def test_an_undersized_offence_count_still_reports_every_line
    in_repo(RUBOCOP_YML) do |root|
      write(root, "test/support/admin_test_case.rb", <<~RUBY)
        class AdminTestCase < ActiveSupport::TestCase
          logger.info("not a definition")
          logger.info("not a definition either")
        end
      RUBY

      sizes = call(root)

      assert_equal 4, sizes.fetch("test/support/admin_test_case.rb")
    end
  end

  def test_a_leaf_test_is_not_measured
    in_repo(RUBOCOP_YML) do |root|
      write(root, "test/models/user_test.rb", <<~RUBY)
        class UserTest < ActiveSupport::TestCase
          def test_it_saves
            assert User.new.save
          end
        end
      RUBY

      refute_includes call(root).keys, "test/models/user_test.rb"
    end
  end

  def test_a_dummy_app_concern_is_not_measured
    in_repo(RUBOCOP_YML) do |root|
      write(root, "test/dummy/app/models/concerns/payable.rb", <<~RUBY)
        module Payable
          def total
            1
          end
        end
      RUBY

      refute_includes call(root).keys, "test/dummy/app/models/concerns/payable.rb"
    end
  end

  # RuboCop's own team skips the cop's investigation entirely; nothing here reads `Enabled`.
  def test_a_disabled_cop_measures_nothing
    in_repo(DISABLED_YML) do |root|
      write(root, "test/support/admin_test_case.rb", <<~RUBY)
        class AdminTestCase < ActiveSupport::TestCase
          def sign_in_as_admin; end
        end
      RUBY

      assert_empty call(root)
    end
  end

  def test_a_target_that_never_requires_shipshape_still_measures
    in_repo(NO_REQUIRE_YML) do |root|
      write(root, "test/support/admin_test_case.rb", <<~RUBY)
        class AdminTestCase < ActiveSupport::TestCase
          def sign_in_as_admin; end
        end
      RUBY

      assert_equal 3, call(root).fetch("test/support/admin_test_case.rb")
    end
  end

  private

  def call(root)
    lines = Shipshape::BaseTestClassLines.new(directory: root, config: File.join(root, ".rubocop.yml"))

    cold = lines.call
    warm = lines.call

    assert_equal cold, warm, "a second, warm-cache run over the same directory must agree with the first"

    warm
  end

  def write(root, path, contents)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end

  # RUBYOPT puts the gem on the subprocess's load path; `companion.rb` is the second
  # inspectable file that turns `--parallel` on.
  def in_repo(config)
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip

    Dir.mktmpdir("shipshape-lines") do |root|
      File.write(File.join(root, ".rubocop.yml"), config)
      write(root, "companion.rb", "class Companion\nend\n")
      yield(root)
    end
  ensure
    ENV["RUBYOPT"] = was
  end
end
