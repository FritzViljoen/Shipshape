# frozen_string_literal: true

require "test_helper"
require "shipshape/base_test_class_lines"

# A real directory and a real `rubocop` subprocess, run through the same cop that counts
# `Shipshape/BaseTestClassGrowth`'s offences - classification happens once, not twice here.
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

  # No `require:` at all - a `--format` naming an unresolved class crashes rubocop outright,
  # unlike `Offences`, which just finds nothing.
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

  # `handle_body` recurses into an `if`, a block or `class << self` to find definitions, but
  # the class's own span - not the definitions inside it - is what is measured.
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

  # A base class holding zero definitions still has a span - all the lines the ratchet must
  # watch for a class golfed down to nothing but plain, unclassified statements.
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

  # `Guards` already reads `Enabled` from the resolved config; this asks RuboCop's own team to
  # skip the cop's investigation entirely rather than building a second way to ask.
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
    Shipshape::BaseTestClassLines.new(directory: root, config: File.join(root, ".rubocop.yml")).call
  end

  def write(root, path, contents)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end

  # RuboCop runs as a subprocess, so it needs the gem on its load path the way a real
  # consumer would have it from the Gemfile - RUBYOPT says that to the child without teaching
  # BaseTestClassLines a test-only argument.
  def in_repo(config)
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip

    Dir.mktmpdir("shipshape-lines") do |root|
      File.write(File.join(root, ".rubocop.yml"), config)
      yield(root)
    end
  ensure
    ENV["RUBYOPT"] = was
  end
end
