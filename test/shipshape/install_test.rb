# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "tmpdir"

# Watched to fail: removing the `File.exist?` guard in Install#call reddens the
# does-not-overwrite case, and it is the one that matters — a generator that clobbers a
# file the application has since edited has taken a decision that was never its own.
class InstallTest < Minitest::Test
  include CopRunner

  def everything
    Shipshape::Install::FILES + Shipshape::Install::TESTS + Shipshape::Install::TASKS
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

  def test_it_writes_every_base_class
    in_app do |root|
      report = install(root)

      assert_equal everything.length, report[:written].length
      assert_empty report[:skipped]
      assert_path_exists File.join(root, "app/shipshape/command.rb")
      assert_path_exists File.join(root, "app/shipshape/legacy_query.rb")
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

      target = File.join(root, "app/shipshape/command.rb")
      File.write(target, "# mine now\n")

      report = install(root)

      assert_empty report[:written]
      assert_equal everything.length, report[:skipped].length,
        "Once written, the file is the application's."
      assert_equal "# mine now\n", File.read(target)
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

      refute_path_exists File.join(root, "app/commands")
      refute_path_exists File.join(root, "app/queries"),
        "The base classes define the shapes; they are not instances of them. `Command` is not a command, so they sit outside the governed trees and no cop classifies them."
    end
  end

  def test_it_writes_every_class_the_default_config_names
    defaults = YAML.load_file(Shipshape::CONFIG_DEFAULT.to_s)
    named = defaults.fetch("Shipshape/CallGraph").fetch("BaseClasses").values.flatten
    generated = %w[Workflow Command Query IoQuery IoCommand LegacyQuery LegacyCommand Shape]

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

      assert_includes report[:written], "lib/shapes/command.rb"
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
