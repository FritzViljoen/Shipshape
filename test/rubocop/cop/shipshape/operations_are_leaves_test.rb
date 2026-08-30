# frozen_string_literal: true

require "test_helper"

# Watched to fail, as `a-guard-states-its-limit` requires:
#
# - Making `check_depth` return early reddens the second-level tests.
# - Making `check_door` return early reddens the overridden-door test.
# - Dropping the `self_type?` check reddens the instance-`call` test, which is the method
#   every operation must define.
class OperationsAreLeavesTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OperationsAreLeaves

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => { "command" => ["Command"], "shape" => ["Shape"] },
      "Matrix" => { "command" => ["shape"], "shape" => [] },
    },
  }.freeze

  # The superclass has to exist on disk: the kind is decided by what a class inherits.
  TREE = {
    "app/commands/log_in.rb" => "class LogIn < Command\n  def anonymous_call; end\nend\n",
    # Filed with the operations it is the base class for — which is where stratum keeps it,
    # and where resolving the constant answers "command".
    "app/commands/command.rb" => "class Command\nend\n",
  }.freeze

  COMMAND = "app/commands/admin_upload.rb"

  # The fail-open review found: `AdminUpload < PublicUpload` was public, inheriting an
  # `anonymous_call` nothing at its own definition mentioned.
  def test_a_second_level_of_inheritance_is_an_offence
    found = check("class AdminUpload < LogIn\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`AdminUpload` inherits from `LogIn`, which is already a command"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("class AdminUpload < LogIn\nend\n").first.message

    assert_includes message, "WHY: A base class is inherited exactly once"
    assert_includes message, "runs unauthenticated"
    assert_includes message, "INSTEAD:"
    assert_includes message, "a collaborator, not an ancestor"
  end

  def test_one_level_from_the_base_class_is_the_shape
    assert_empty check("class AdminUpload < Command\n  def call; end\nend\n")
  end

  # The door is where the permission check, the transaction and the type assertion live.
  def test_overriding_the_door_is_an_offence
    found = check(<<~RUBY)
      class AdminUpload < Command
        def self.call(**arguments)
          new(**arguments).call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "owns `self.call`, which is the door"
  end

  # The instance method is the one every operation must define.
  def test_the_instance_call_is_not_the_door
    assert_empty check("class AdminUpload < Command\n  def call\n    success(:done)\n  end\nend\n")
  end

  # **A base class filed with its operations is still a base class.** Resolving `Command`
  # in a repository that keeps `app/commands/command.rb` answers "command", so every correct
  # operation looked like a second level — 22 of stratum's 80 files, all false.
  def test_a_base_class_kept_beside_its_operations_is_not_a_second_level
    assert_empty check("class AdminUpload < Command\n  def call; end\nend\n")
  end

  def test_a_shape_is_outside_the_operation_kinds
    assert_empty offences("class Line < Invoice\nend\n", cop_class: COP,
                                                        path: "app/shapes/line.rb", files: TREE, other_cops: LAYOUT)
  end

  # Depth is measured through governed files only.
  def test_inheriting_from_something_the_layout_does_not_declare_is_left_alone
    assert_empty check("class AdminUpload < ActiveRecord::Base\nend\n")
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, files: TREE, other_cops: LAYOUT)
  end
end
