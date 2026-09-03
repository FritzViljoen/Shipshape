# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `check_depth` return early reddens the second-level tests; making
# `check_door` return early reddens the overridden-door test; dropping the `self_type?` check
# reddens the instance-`call` test, which is the method every operation must define.
class OperationsAreLeavesTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OperationsAreLeaves

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => { "command" => %w[Command ApplicationMailer], "shape" => ["Shape"] },
      "Matrix" => { "command" => ["shape"], "shape" => [] },
    },
  }.freeze

  TREE = {
    "app/commands/log_in.rb" => "class LogIn < Command\n  def anonymous_call; end\nend\n",
    "app/commands/command.rb" => "class Command\nend\n",
    "app/commands/theirs.rb" => "class Theirs\n  def self.call; end\nend\n",
    "app/commands/a_mailer.rb" => "class AMailer < ApplicationMailer\nend\n",
  }.freeze

  COMMAND = "app/commands/admin_upload.rb"

  def test_a_second_level_of_inheritance_is_an_offence
    found = check("class AdminUpload < LogIn\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`AdminUpload` inherits from `LogIn`, which is already a command",
      "The fail-open review found: `AdminUpload < PublicUpload` was public, inheriting an `anonymous_call` nothing at its own definition mentioned."
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

  def test_overriding_the_door_is_an_offence
    found = check(<<~RUBY)
      class AdminUpload < Command
        def self.call(**arguments)
          new(**arguments).call
        end
      end
    RUBY

    assert_equal 1, found.length,
      "The door is where the permission check, the transaction and the type assertion live."
    assert_includes found.first.message, "owns `self.call`, which is the door"
  end

  def test_the_instance_call_is_not_the_door
    assert_empty check("class AdminUpload < Command\n  def call\n    success(:done)\n  end\nend\n")
  end

  # A base class filed with its operations is still a base class: resolving `Command` in a
  # repository keeping `app/commands/command.rb` made 22 of stratum's 80 files false positives.
  def test_a_base_class_kept_beside_its_operations_is_not_a_second_level
    assert_empty check("class AdminUpload < Command\n  def call; end\nend\n")
  end

  # A plain class in a governed tree resolves to a kind by path alone, and is not ours.
  def test_a_parent_that_inherits_nothing_of_ours_is_not_a_second_level
    assert_empty check("class AdminUpload < Theirs\n  def call; end\nend\n")
  end

  # Applying the depth rule to `ApplicationMailer` fired on every mailer in chatwoot.
  def test_a_framework_hierarchy_has_no_depth_rule
    assert_empty check("class WelcomeMailer < AMailer\n  def call; end\nend\n")
  end

  def test_a_shape_is_outside_the_operation_kinds
    assert_empty offences("class Line < Invoice\nend\n", cop_class: COP,
                                                        path: "app/shapes/line.rb", files: TREE, other_cops: LAYOUT)
  end

  def test_inheriting_from_something_the_layout_does_not_declare_is_left_alone
    assert_empty check("class AdminUpload < ActiveRecord::Base\nend\n")
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, files: TREE, other_cops: LAYOUT)
  end
end
