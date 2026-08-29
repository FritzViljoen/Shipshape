# frozen_string_literal: true

require "test_helper"
require "shipshape/install"

# Watched to fail, as `a-guard-states-its-limit` requires:
#
# - Making `checks_permission?` answer true reddens the gutted-door tests.
# - Making `authorisation_installed?` answer true reddens the opted-out test — the one that
#   keeps this cop silent in an application that never asked for authorisation.
# - Making `door?` answer true reddens the not-a-door test.
class EveryDoorChecksPermissionTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::EveryDoorChecksPermission

  WITH_AUTH = { "app/shipshape/permission.rb" => "module Permission\nend\n" }.freeze

  GUTTED = <<~RUBY
    class Command
      def self.call(**arguments)
        ActiveRecord::Base.transaction { new(**arguments).call }
      end
    end
  RUBY

  def test_a_door_that_lost_its_check_is_an_offence
    found = offences(GUTTED, cop_class: COP, path: "app/shipshape/command.rb", files: WITH_AUTH)

    assert_equal 1, found.length
    assert_includes found.first.message, "`command.rb` is a door and no longer checks a permission"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = offences(GUTTED, cop_class: COP, path: "app/shipshape/command.rb", files: WITH_AUTH).first.message

    assert_includes message, "WHY: `shipshape install` never overwrites your files"
    assert_includes message, "INSTEAD:"
    assert_includes message, "return Result.failure(:forbidden) unless permits?(actor)"
    assert_includes message, "anonymous_call"
  end

  def test_a_door_that_still_checks_is_the_shape
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/shipshape/command.rb", files: WITH_AUTH)
      class Command
        extend Permission

        def self.call(actor: nil, **arguments)
          return Result.failure(:forbidden) unless permits?(actor)

          new(actor: actor, **arguments).call
        end
      end
    RUBY
  end

  # An application that never opted in is not nagged about a check it did not ask for.
  def test_an_application_without_authorisation_is_left_alone
    assert_empty offences(GUTTED, cop_class: COP, path: "app/shipshape/command.rb")
  end

  def test_a_file_that_is_not_a_door_is_left_alone
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/shipshape/result.rb", files: WITH_AUTH)
      class Result
        def self.success(value)
          new(value)
        end
      end
    RUBY
  end

  # Whatever the templates render today, the doors they write must satisfy this cop —
  # otherwise the generator and the guard disagree and one of them is wrong.
  def test_every_door_the_installer_writes_with_auth_satisfies_this_cop
    Dir.mktmpdir("doors") do |root|
      Shipshape::Install.new(root: root, auth: true).call

      COP::DOORS.each do |door|
        source = File.read(File.join(root, "app/shipshape/#{door}.rb"))

        assert_empty offences(source, cop_class: COP, path: "app/shipshape/#{door}.rb", files: WITH_AUTH),
                     "the installer writes a #{door} the guard rejects"
      end
    end
  end
end
