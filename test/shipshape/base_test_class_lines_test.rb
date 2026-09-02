# frozen_string_literal: true

require "test_helper"
require "shipshape/base_test_class_lines"
require "shipshape/canaries"
require "fileutils"

# A real directory and a real subprocess: raw `Dir.glob` once walked into `vendor/bundle` and
# counted a dependency's own tests as base-class growth. Watched to fail: dropping the
# `TargetFinder` swap, or the canary-tree skip, reddens the matching test below.
class BaseTestClassLinesTest < Minitest::Test
  RUBOCOP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false
  YAML

  BASE_CLASS = <<~RUBY
    class AdminTestCase < ActiveSupport::TestCase
      def sign_in_as_admin; end
    end
  RUBY

  def test_a_qualifying_base_class_is_counted
    in_repo do |root|
      write(root, "test/support/admin_test_case.rb", BASE_CLASS)

      lines = call(root)

      assert_equal 3, lines["test/support/admin_test_case.rb"]
    end
  end

  def test_vendored_gem_source_is_not_counted
    in_repo do |root|
      write(root, "vendor/bundle/ruby/3.3.0/gems/somegem-1.0/test/some_test_helper.rb", BASE_CLASS)

      assert_empty call(root)
    end
  end

  def test_the_canary_tree_is_not_counted
    in_repo do |root|
      write(root, "#{Shipshape::Canaries::DIRECTORY}/test/canary_base_test_class.rb", BASE_CLASS)

      assert_empty call(root)
    end
  end

  private

  def call(root)
    Shipshape::BaseTestClassLines.new(directory: root, config: File.join(root, ".rubocop.yml")).call
  end

  def write(root, path, contents)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end

  def in_repo
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip

    Dir.mktmpdir("shipshape-base-test-class-lines") do |root|
      File.write(File.join(root, ".rubocop.yml"), RUBOCOP_YML)
      yield(root)
    end
  ensure
    ENV["RUBYOPT"] = was
  end
end
