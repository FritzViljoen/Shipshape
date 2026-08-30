# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "tmpdir"

# Watched to fail: removing the `File.exist?` guard in Install#call reddens the
# does-not-overwrite case, and it is the one that matters — a generator that clobbers a
# file the application has since edited has taken a decision that was never its own.
class InstallTest < Minitest::Test
  def test_it_writes_every_base_class
    in_app do |root|
      report = Shipshape::Install.new(root: root, auth: true).call

      assert_equal Shipshape::Install::FILES.length, report[:written].length
      assert_empty report[:skipped]
      assert_path_exists File.join(root, "app/shipshape/command.rb")
      assert_path_exists File.join(root, "app/shipshape/legacy_query.rb")
    end
  end

  # Once written, the file is the application's.
  def test_it_never_overwrites
    in_app do |root|
      Shipshape::Install.new(root: root, auth: true).call

      target = File.join(root, "app/shipshape/command.rb")
      File.write(target, "# mine now\n")

      report = Shipshape::Install.new(root: root, auth: true).call

      assert_empty report[:written]
      assert_equal Shipshape::Install::FILES.length, report[:skipped].length
      assert_equal "# mine now\n", File.read(target)
    end
  end

  def test_every_generated_file_is_valid_ruby
    in_app do |root|
      Shipshape::Install.new(root: root, auth: true).call

      Dir[File.join(root, "app/shipshape/*.rb")].each do |path|
        assert RubyVM::InstructionSequence.compile(File.read(path), path), "#{path} did not compile"
      end
    end
  end

  # The base classes define the shapes; they are not instances of them. `Command` is not a
  # command, so they sit outside the governed trees and no cop classifies them.
  def test_they_land_outside_the_governed_trees
    in_app do |root|
      Shipshape::Install.new(root: root, auth: true).call

      refute_path_exists File.join(root, "app/commands")
      refute_path_exists File.join(root, "app/queries")
    end
  end

  # Every name the default configuration lists under BaseClasses has to be a class the
  # installer actually writes, or the config points at nothing and classifies nothing.
  def test_it_writes_every_class_the_default_config_names
    defaults = YAML.load_file(Shipshape::CONFIG_DEFAULT.to_s)
    named = defaults.fetch("Shipshape/CallGraph").fetch("BaseClasses").values.flatten
    generated = %w[Workflow Command Query IoQuery IoCommand LegacyQuery LegacyCommand Shape]

    # The application's own bases and the framework's. Shipshape names them so kinds can be
    # resolved — and so `OperationsAreLeaves` knows a class inheriting one is a first level,
    # not a second — but it does not write them, because they already exist.
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
