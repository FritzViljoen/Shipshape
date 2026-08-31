# frozen_string_literal: true

require "test_helper"

# Watched to fail: dropping the `prose.length <= budget` return reddens the under-budget test;
# counting `processed_source.lines` matching `#` instead of comment tokens reddens the heredoc
# test; dropping the DIRECTIVE filter reddens the directive test.
class CommentBudgetTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CommentBudget

  PATH = "lib/anything.rb"

  def test_prose_over_a_tenth_of_the_code_is_an_offence
    found = check(<<~RUBY)
      # one
      # two
      CANARY = 1
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "2 comment lines against a budget of 0"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("# a\n# b\nCANARY = 1\n").first.message

    assert_includes message, "WHY: A comment is a second copy of a rule"
    assert_includes message, "INSTEAD:"
    assert_includes message, "The reasoning lives in the law"
  end

  def test_a_file_inside_its_budget_is_the_shape
    assert_empty check("# one clause\n#{"CANARY = 1\n" * 10}")
  end

  # A `#` inside a heredoc is the string's content. A cop's `instead:` example is written that
  # way, and charging it would make the cops delete their own messages.
  def test_a_hash_inside_a_heredoc_is_not_a_comment
    assert_empty check(<<~'RUBY')
      EXAMPLE = <<~TEXT
        # or :delete_row
        # or :not_personal
      TEXT
    RUBY
  end

  # Both are addressed to the tool, not the reader.
  def test_a_directive_is_not_charged
    assert_empty check("# frozen_string_literal: true\nCANARY = 1\n")
    assert_empty check("# rubocop:disable Style/Doc\nCANARY = 1\n# rubocop:enable Style/Doc\n")
  end

  # The line was already there. A reader pays nothing extra for what sits at its end.
  def test_a_trailing_comment_is_not_charged
    assert_empty check("CANARY = 1 # why this number\n")
  end

  def test_the_budget_is_configurable
    source = "# a\n# b\n#{"CANARY = 1\n" * 10}"

    assert_empty offences(source, cop_class: COP, path: PATH, cop_config: { "Max" => 20 })
    assert_equal 1, offences(source, cop_class: COP, path: PATH, cop_config: { "Max" => 10 }).length
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
