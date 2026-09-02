# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "tmpdir"

# Watched to fail: inverting `rspec_suite?` reddens the framework tests. Removing the `File.exist?` guard in Install#call reddens the
# does-not-overwrite case, and it is the one that matters — a generator that clobbers a
# file the application has since edited has taken a decision that was never its own.
class InstallTest < Minitest::Test
  include CopRunner

  def everything
    Shipshape::Install::FILES + Shipshape::Install::TESTS + Shipshape::Install::TASKS +
      Shipshape::Install::BASE_TESTS
  end

  def read_installed(root, relative)
    File.read(File.join(root, relative))
  end

  def install(root)
    Shipshape::Install.new(root: root, auth: true, view_components: true).call
  end

  # **The templates are ERB, so no cop can read one.** `<%- if auth -%>` is not Ruby, and a
  # `.rb.tt` in a cop's Include is a parse error rather than an offence. What ships is the
  # rendered file, so `Shipshape/CommentBudget` is run over that, in both installs.
  def test_nothing_installed_is_over_its_comment_budget
    [true, false].each do |auth|
      in_app do |root|
        Shipshape::Install.new(root: root, auth: auth, view_components: true).call

        over = Dir[File.join(root, "**/*.rb")].sort.filter_map do |path|
          found = offences(File.read(path), cop_class: RuboCop::Cop::Shipshape::CommentBudget,
                           path: path.delete_prefix("#{root}/"))
          "#{File.basename(path)}: #{found.first.message.lines.first.strip}" if found.any?
        end

        assert_empty over, "auth: #{auth}"
      end
    end
  end

  # `test_call` is declared entirely inside each template's auth branch, so a comment naming it
  # must be too. Watched to fail: putting the line above `<%- if auth -%>` in `write.rb.tt`
  # reddens this, because the rendered `Write` then describes a method it does not define.
  def test_a_non_auth_install_has_no_comment_promising_test_call
    in_app do |root|
      Shipshape::Install.new(root: root, auth: false).call

      offenders = Dir[File.join(root, "app/shipshape/*.rb")].sort.filter_map do |path|
        source = File.read(path)
        next if source.include?("def self.test_call")

        promising = source.lines.select { |line| line.include?("test_call") && !line.match?(/no `test_call`/i) }
        "#{path.delete_prefix("#{root}/")}: #{promising.join}" if promising.any?
      end

      assert_empty offenders, "a comment describes `test_call` in a kind whose non-auth render has none"
    end
  end

  # A guard written in the wrong framework is a file that never runs: lobsters got two Minitest
  # ones into a suite that is entirely RSpec. Detected from the tree, never asked.
  def test_a_repository_with_a_spec_directory_gets_rspec_guards
    in_app do |root|
      FileUtils.mkdir_p(File.join(root, "spec"))

      report = Shipshape::Install.new(root: root, auth: true).call

      assert_includes report[:written], "spec/shipshape/personal_data_is_erasable_spec.rb"
      refute_path_exists File.join(root, "test/shipshape"),
                         "an RSpec repository has no test/ for these to run in"
      assert_includes read_installed(root, "spec/shipshape/operations_expose_nothing_spec.rb"),
                      "RSpec.describe"
    end
  end

  def test_a_repository_without_one_gets_minitest_guards
    in_app do |root|
      report = Shipshape::Install.new(root: root, auth: true).call

      assert_includes report[:written], "test/shipshape/personal_data_is_erasable_test.rb"
      assert_includes read_installed(root, "test/shipshape/operations_expose_nothing_test.rb"),
                      "TestCase"
    end
  end

  # An installed file nothing inherits is coverage-shaped: the two guards that need a booted
  # application are the only proof that `test_case.rb` is wired to anything at all.
  def test_the_installed_guards_inherit_the_installed_base_class
    in_app do |root|
      Shipshape::Install.new(root: root, auth: true).call

      %w[test/shipshape/operations_expose_nothing_test.rb
         test/shipshape/personal_data_is_erasable_test.rb].each do |relative|
        contents = read_installed(root, relative)

        assert_includes contents, 'require_relative "test_case"', relative
        assert_includes contents, "< TestCase", relative
      end
    end
  end

  # RSpec's own sharing is a mixin (`shared_context`, `config.include`) — the shape
  # `a-test-inherits-what-it-needs` closes — so there is no honest RSpec form of this class.
  def test_the_base_test_class_is_written_for_minitest_only
    in_app do |root|
      report = Shipshape::Install.new(root: root).call

      assert_includes report[:written], "test/shipshape/test_case.rb"
      assert_includes read_installed(root, "test/shipshape/test_case.rb"), "ActiveSupport::TestCase"
    end
  end

  def test_the_base_test_class_is_not_written_for_rspec
    in_app do |root|
      FileUtils.mkdir_p(File.join(root, "spec"))

      report = Shipshape::Install.new(root: root).call

      refute_includes report[:written], "spec/shipshape/test_case.rb"
      refute_path_exists File.join(root, "spec/shipshape/test_case.rb")
    end
  end

  def test_it_writes_every_base_class
    in_app do |root|
      report = install(root)

      assert_equal everything.length, report[:written].length
      assert_empty report[:skipped]
      assert_path_exists File.join(root, "app/shipshape/write.rb")
      assert_path_exists File.join(root, "app/shipshape/legacy_read.rb")
      assert_path_exists File.join(root, "lib/tasks/shipshape_routes.rake")
    end
  end

  def test_the_view_component_base_is_written_only_when_asked_for
    in_app do |root|
      Shipshape::Install.new(root: root, auth: true).call

      refute_path_exists File.join(root, "app/shipshape/application_view_component.rb"),
        "**The one generated file that can stop a boot**, because it inherits from the view_component gem. Everything else here is a PORO that loads anywhere, so everything else is written unconditionally."
      assert_path_exists File.join(root, "app/shipshape/holds_no_records.rb"),
                         "the rule itself is not optional; only the class that needs the gem is"
    end
  end

  def test_the_view_component_base_is_written_when_asked_for
    in_app { |root| assert_path_exists File.join(install(root) && root, "app/shipshape/application_view_component.rb") }
  end

  def test_it_writes_the_guards_that_need_a_booted_application
    in_app do |root|
      install(root)

      assert_path_exists File.join(root, "test/shipshape/operations_expose_nothing_test.rb"),
        "A guard that needs the application loaded is a test, not a cop, and it lands in the suite rather than in `app/`."
    end
  end

  def test_it_never_overwrites
    in_app do |root|
      install(root)

      target = File.join(root, "app/shipshape/write.rb")
      File.write(target, "# mine now\n")

      report = install(root)

      assert_empty report[:written]
      assert_equal "# mine now\n", File.read(target), "Once written, the file is the application's."
    end
  end

  def test_a_file_absent_is_written
    in_app do |root|
      report = install(root)

      assert_includes report[:written], "app/shipshape/write.rb"
      assert_empty report[:skipped]
      assert_empty report[:diverged]
    end
  end

  def test_a_file_present_and_identical_is_kept_not_diverged
    in_app do |root|
      install(root)

      report = install(root)

      assert_empty report[:written]
      assert_equal everything.length, report[:skipped].length
      assert_empty report[:diverged]
    end
  end

  def test_a_file_present_and_differing_is_reported_and_left_untouched
    in_app do |root|
      install(root)
      target = File.join(root, "app/shipshape/write.rb")
      File.write(target, "# mine now\n")

      report = install(root)

      assert_includes report[:diverged], "app/shipshape/write.rb"
      refute_includes report[:skipped], "app/shipshape/write.rb"
      assert_equal everything.length - 1, report[:skipped].length,
        "everything else still matches what the gem would write"
      assert_equal "# mine now\n", File.read(target), "the adopter's file is never touched"

      new_file = "#{target}.new"
      assert_path_exists new_file
      refute_equal "# mine now\n", File.read(new_file)

      in_app { |fresh| install(fresh) && assert_equal(read_installed(fresh, "app/shipshape/write.rb"), File.read(new_file)) }
    end
  end

  # A `.new` outlives the divergence that wrote it. Adopting the gem's version leaves the file
  # beside it referring to nothing; without this, `diverged` silently goes empty and the leftover
  # is never named again.
  def test_a_new_file_no_longer_needed_is_reported_stale_and_left_alone
    in_app do |root|
      install(root)
      target = File.join(root, "app/shipshape/write.rb")
      File.write(target, "# mine now\n")
      install(root)
      new_file = "#{target}.new"

      File.write(target, File.read(new_file))
      report = install(root)

      assert_includes report[:stale], "app/shipshape/write.rb"
      assert_empty report[:diverged]
      assert_path_exists new_file, "reported, never deleted"
    end
  end

  def test_a_new_file_still_diverging_is_not_reported_stale
    in_app do |root|
      install(root)
      target = File.join(root, "app/shipshape/write.rb")
      File.write(target, "# mine now\n")
      install(root)

      report = install(root)

      assert_includes report[:diverged], "app/shipshape/write.rb"
      assert_empty report[:stale]
    end
  end

  def test_every_generated_file_is_valid_ruby
    in_app do |root|
      install(root)

      Dir[File.join(root, "{app,test}/shipshape/*.rb")].each do |path|
        assert RubyVM::InstructionSequence.compile(File.read(path), path), "#{path} did not compile"
      end
    end
  end

  def test_they_land_outside_the_governed_trees
    in_app do |root|
      install(root)

      refute_path_exists File.join(root, "app/writes")
      refute_path_exists File.join(root, "app/reads"),
        "The base classes define the shapes; they are not instances of them. `Write` is not a write, so they sit outside the governed trees and no cop classifies them."
    end
  end

  def test_it_writes_every_class_the_default_config_names
    defaults = YAML.load_file(Shipshape::CONFIG_DEFAULT.to_s)
    named = defaults.fetch("Shipshape/CallGraph").fetch("BaseClasses").values.flatten
    generated = %w[Workflow Write Read IoRead IoWrite LegacyRead LegacyWrite Shape]

    # Named so kinds resolve and so a class inheriting one reads as a first level. Shipshape
    # does not write them, because they already exist.
    theirs = %w[
      ApplicationRecord ActiveRecord::Base
      ApplicationViewComponent ViewComponent::Base
      ApplicationMailer ActionMailer::Base
      ApplicationJob ActiveJob::Base ApplicationCable::Channel ActionCable::Channel::Base
      ApplicationController ActionController::Base ActionController::API
    ]

    (named - theirs).each do |name|
      assert_includes generated, name, "BaseClasses names #{name} but nothing generates it"
    end
  end

  def test_a_directory_may_be_chosen
    in_app do |root|
      report = Shipshape::Install.new(root: root, directory: "lib/shapes").call

      assert_includes report[:written], "lib/shapes/write.rb"
    end
  end

  def test_the_root_is_asserted_at_the_seam
    assert_raises(ArgumentError) { Shipshape::Install.new(root: nil) }
    assert_raises(ArgumentError) { Shipshape::Install.new(root: Pathname.new("/tmp")) }
  end

  private

  def in_app
    Dir.mktmpdir("shipshape-app") { |root| yield(root) }
  end
end
