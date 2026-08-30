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

  # Construction is what is closed: `call` is the only way in, and it is where the
  # permission check, the transaction and the return-type assertion live.
  def test_building_an_operation_directly_is_a_bypass
    found = check("Settle.send(:new, amount: 1)")

    assert_equal 1, found.length
    assert_includes found.first.message, "`send(:new)` builds an operation without going through the door"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("Settle.send(:new, amount: 1)").first.message

    assert_includes message, "WHY: The constructor is private"
    assert_includes message, "`private` is a convention"
    assert_includes message, "INSTEAD:"
    assert_includes message, "SettleInvoice.call(actor: actor, invoice_id: 1)"
  end

  def test_every_sender_in_the_family_is_caught
    found = check(<<~RUBY)
      a = Settle.send(:new)
      b = Settle.__send__(:new)
      c = Settle.public_send(:new)
      d = op.send(:__perform__)
      [a, b, c, d]
    RUBY

    assert_equal 4, found.length
  end

  def test_the_door_itself_is_not_a_bypass
    assert_empty check("Settle.call(actor: actor, amount: 1)")
  end

  # The forwarding method the base class uses to reach a private entry point. Reaching it
  # from outside runs the operation with none of the door's guarantees.
  # `allocate` is public on every Ruby class and skips `initialize`, so hiding `new` alone
  # left `Settle.allocate.__perform__(actor)` running unauthenticated. Found by running it.
  def test_allocate_is_a_bypass_too
    assert_equal 1, check("Settle.send(:allocate)").length
  end

  def test_the_forwarder_is_a_bypass_too
    found = check("op.send(:__perform__)")

    assert_equal 1, found.length
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
