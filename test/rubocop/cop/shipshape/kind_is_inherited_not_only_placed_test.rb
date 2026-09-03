# frozen_string_literal: true

require "test_helper"

# Watched to fail: skipping the nil-parent branch in `check_inheritance` reddens the bare-class
# test; `rooted_in_a_base?` returning `true` unconditionally reddens the unrelated-parent test;
# `declares_this_file?` returning `true` unconditionally reddens both the sibling and nested test.
class KindIsInheritedNotOnlyPlacedTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::KindIsInheritedNotOnlyPlaced

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => { "command" => %w[Command ApplicationMailer] },
      "Matrix" => { "command" => ["shape"], "shape" => [] },
    },
  }.freeze

  COMMAND = "app/commands/settle_invoice.rb"

  def test_a_bare_class_with_no_superclass_is_an_offence
    found = check("class SettleInvoice\n  def call; end\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleInvoice` is a command by placement, and " \
                                          "names no superclass at all"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("class SettleInvoice\nend\n").first.message

    assert_includes message, "WHY: Every cop gated on `command` assumes"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class SettleInvoice < Command"
  end

  def test_inheriting_the_declared_base_directly_is_the_shape
    assert_empty check("class SettleInvoice < Command\n  def call; end\nend\n")
  end

  def test_inheriting_a_base_transitively_through_a_governed_file_is_the_shape
    found = offences(
      "class SettleInvoice < AdminCommand\n  def call; end\nend\n",
      cop_class: COP, path: COMMAND, other_cops: LAYOUT,
      files: { "app/commands/admin_command.rb" => "class AdminCommand < Command\nend\n" },
    )

    assert_empty found
  end

  def test_inheriting_something_unrelated_is_an_offence
    found = check("class SettleInvoice < StandardError\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message,
                    "neither `StandardError` nor anything it inherits is `Command`"
  end

  # `shape` names no BaseClasses entry in this layout: left alone rather than guessed at.
  def test_a_kind_with_no_declared_base_is_left_alone
    found = offences("class Basket\nend\n", cop_class: COP, path: "app/shapes/basket.rb",
                                            other_cops: LAYOUT)

    assert_empty found
  end

  # `an-operation-is-a-leaf` names the same shape: a base class filed beside its own kind is
  # still a base class, and it cannot inherit itself.
  def test_the_base_class_filed_beside_its_own_kind_is_exempt
    found = offences("class Command\nend\n", cop_class: COP, path: "app/commands/command.rb",
                                             other_cops: LAYOUT)

    assert_empty found
  end

  def test_a_sibling_class_in_the_same_file_is_left_alone
    found = check(<<~RUBY)
      class SettleInvoiceError < StandardError
      end

      class SettleInvoice < Command
        def call; end
      end
    RUBY

    assert_empty found
  end

  def test_a_nested_helper_class_is_left_alone
    found = check(<<~RUBY)
      class SettleInvoice < Command
        class Helper
        end

        def call; end
      end
    RUBY

    assert_empty found
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, other_cops: LAYOUT)
  end
end
