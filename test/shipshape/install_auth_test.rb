# frozen_string_literal: true

require "test_helper"
require "shipshape/install"

# Authorisation is opt-in because this gem installs into codebases that already run. Base
# classes demanding an actor on day one would stop every call site at once, which is an
# outage rather than a migration.
#
# Watched to fail: make `files` ignore `AUTH_ONLY` and the default-install test reddens;
# hard-code `auth` to true in `template`'s binding and every off test reddens.
class InstallAuthTest < Minitest::Test
  DOORS = %w[command io_command legacy_command query io_query legacy_query workflow].freeze

  def test_the_default_install_writes_no_authorisation
    written = install(auth: false)

    refute_includes written.keys, "permission.rb"

    DOORS.each do |door|
      source = written.fetch("#{door}.rb")

      refute_includes source, "permits?", "#{door} checks a permission it was not asked for"
      refute_includes source, "extend Permission", door
      refute_includes source, "anonymous?", door
    end
  end

  def test_asking_for_authorisation_writes_the_check_into_every_door
    written = install(auth: true)

    assert_includes written.keys, "permission.rb"

    DOORS.each do |door|
      assert_includes written.fetch("#{door}.rb"), "permits?", "#{door} is a door with no check"
    end
  end

  # A door that cannot be parsed is worse than one that refuses nothing.
  def test_both_variants_are_valid_ruby
    [false, true].each do |auth|
      install(auth: auth).each do |name, source|
        assert RubyVM::InstructionSequence.compile(source), "#{name} (auth: #{auth}) does not parse"
      end
    end
  end

  def test_the_workflow_keeps_its_steps_either_way
    [false, true].each do |auth|
      assert_includes install(auth: auth).fetch("workflow.rb"), "class Workflow"
    end
  end

  private

  def install(auth:)
    Dir.mktmpdir("shipshape-auth") do |root|
      Shipshape::Install.new(root: root, auth: auth).call

      Dir[File.join(root, "app/shipshape/*.rb")].to_h { |path| [File.basename(path), File.read(path)] }
    end
  end
end
