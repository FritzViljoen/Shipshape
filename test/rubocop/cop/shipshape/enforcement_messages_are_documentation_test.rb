# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `documents?` answer true unconditionally reddens both bare-message tests;
# making `cop_file?` answer true unconditionally reddens the not-a-cop test; dropping `:dstr` from
# `literal` reddens the interpolated-message test. A heredoc with no interpolation parses as
# `:str`, so it does not prove that branch — this was found by removal, which is the point of doing
class EnforcementMessagesAreDocumentationTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::EnforcementMessagesAreDocumentation

  PATH = "lib/rubocop/cop/app/no_shouting.rb"

  def test_a_bare_message_constant_is_an_offence
    found = check(<<~RUBY)
      class NoShouting < Base
        MSG = "Do not use lifecycle callbacks."

        def on_send(node)
          add_offense(node)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`MSG` states a rule without saying why"
  end

  def test_a_bare_inline_message_is_an_offence
    found = check(<<~RUBY)
      class NoShouting < Base
        def on_send(node)
          add_offense(node, message: "Controller should not branch here")
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "This message states a rule"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class NoShouting < Base
        MSG = "Nope."

        def on_send(node)
          add_offense(node)
        end
      end
    RUBY

    assert_includes message, "WHY: A message that only says something is wrong"
    assert_includes message, "INSTEAD:"
    assert_includes message, "add_offense(node, message: explain("
  end

  def test_a_message_carrying_both_sections_passes
    assert_empty check(<<~RUBY)
      class NoShouting < Base
        MSG = <<~TEXT
          `before_save` hides work behind `save`.

          WHY: The caller reads one method and gets several, in an order nothing states.

          INSTEAD:
              RecalculateTotals.call(booking: @booking)
        TEXT

        def on_send(node)
          add_offense(node)
        end
      end
    RUBY
  end

  def test_an_interpolated_message_is_read_and_still_bare
    found = check(<<~'RUBY')
      class NoShouting < Base
        def on_send(node)
          add_offense(node, message: "`#{node.method_name}` is not allowed here")
        end
      end
    RUBY

    assert_equal 1, found.length,
      "The common bad shape: a message that names the construct and stops. Interpolation makes it a `dstr`, which is a different node than a plain string and has to be read as one."
  end

  # The reason `explain` exists: a call cannot be read, so it is trusted, and its signature
  # is what makes the three parts unskippable.
  def test_a_message_built_by_a_call_is_trusted
    assert_empty check(<<~RUBY)
      class NoShouting < Base
        def on_send(node)
          add_offense(node, message: explain("Nope.", because: "Reasons.", instead: "Code."))
        end
      end
    RUBY
  end

  # A file is a cop because it calls `add_offense`, not because of where it sits.
  def test_a_file_that_raises_no_offence_is_not_a_cop
    assert_empty check(<<~RUBY)
      class Announcement
        MSG = "Hello."
      end
    RUBY
  end

  # It reads sections, never sense — the law says so, and this pins it so nobody reads the
  # green build as meaning the example was any good.
  def test_it_does_not_judge_whether_the_example_is_any_good
    assert_empty check(<<~RUBY)
      class NoShouting < Base
        MSG = "Nope. WHY: because. INSTEAD: do something else."

        def on_send(node)
          add_offense(node)
        end
      end
    RUBY
  end

  def test_markers_with_nothing_after_them_are_not_a_message
    found = check(<<~RUBY)
      class NoShouting < Base
        MSG = "Do not use lifecycle callbacks. WHY: INSTEAD:"

        def on_send(node)
          add_offense(node)
        end
      end
    RUBY

    assert_equal 1, found.length,
      "Checking only that the markers appear accepted a message with no reason and no example — the one cop policing message quality taking exactly what it forbids."
  end

  def test_markers_with_nothing_after_them_are_not_a_message
    found = check(<<~RUBY)
      class NoShouting < Base
        MSG = "Do not use lifecycle callbacks. WHY: INSTEAD:"

        def on_send(node)
          add_offense(node)
        end
      end
    RUBY

    assert_equal 1, found.length,
      "Checking only that the markers appear accepted a message with no reason and no example — the one cop policing message quality taking exactly what it forbids."
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
