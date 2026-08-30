# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Emptying `SENDERS` reddens the bypass tests.
# - Making `literal_name` answer the source rather than a literal's value reddens the
#   dynamic-send test, which is the stated blind spot.
# - Removing `Exclude` from the config reddens nothing here, so the base classes' own
#   legitimate `send` is covered by `test_the_generated_base_classes_are_not_bypasses` in
#   `install_auth_test.rb` instead.
class NoEntryPointBypassTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoEntryPointBypass

  PATH = "app/controllers/things_controller.rb"

  def test_send_to_the_entry_point_is_a_bypass
    found = check("Settle.new(amount: 1).send(:call)")

    assert_equal 1, found.length
    assert_includes found.first.message, "`send(:call)` reaches an operation's private entry point"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("Settle.new(amount: 1).send(:call)").first.message

    assert_includes message, "WHY: That entry point is private"
    assert_includes message, "`private` is a convention"
    assert_includes message, "INSTEAD:"
    assert_includes message, "SettleInvoice.call(actor: actor, invoice_id: 1)"
  end

  def test_every_sender_in_the_family_is_caught
    found = check(<<~RUBY)
      a = op.send(:call)
      b = op.__send__(:call)
      c = op.public_send(:anonymous_call)
      d = op.method(:call)
      [a, b, c, d]
    RUBY

    assert_equal 4, found.length
  end

  def test_the_door_itself_is_not_a_bypass
    assert_empty check("Settle.call(actor: actor, amount: 1)")
  end

  # A method name this cannot read is the stated blind spot, not a silent pass: reporting it
  # would mean flagging every `send` in the codebase.
  def test_a_dynamic_method_name_is_not_reported
    assert_empty check("op.send(verb)")
  end

  def test_sending_something_else_is_not_a_bypass
    assert_empty check("op.send(:to_h)")
  end

  private

  def check(body)
    offences("class ThingsController\n  def show\n    #{body}\n  end\nend\n",
             cop_class: COP, path: PATH)
  end
end
