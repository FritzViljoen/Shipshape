# frozen_string_literal: true

require "test_helper"

# **Every template ships into somebody else's application, and a comment there is a second
# copy of a law.** The law is the copy that gets corrected; the one in the file is the one
# that goes on being believed. Three comments here were already false when this was written —
# `io_command` describing what happens "after the transaction" it opens none of, `workflow`
# telling views to ask `permissions` after that method was made private, and `query` claiming
# an audit entry a query has never written.
#
# So a template carries at most **5% of its own code in comment lines** — the header line that
# says what the file is, and the handful of whys that would be lost with nowhere else to sit.
# Everything else lives in `docs/laws/`, where it is reviewed when the rule changes.
#
# Watched to fail: paste any four-line comment back into `lib/shipshape/templates/query.rb.tt`
# and this reddens naming that file, its count and its budget.
class ShippedCodeIsUncommentedTest < Minitest::Test
  BUDGET = 5

  TEMPLATES = Dir[File.expand_path("../../lib/shipshape/templates/*.tt", __dir__)].freeze

  # A pragma, not prose. It is required on every file and says nothing about the code, so
  # counting it would put the smallest templates over budget on a line they cannot drop.
  PRAGMA = "# frozen_string_literal: true"

  # **This counts lines, not comments.** A `#` opening a line inside a heredoc reads as one,
  # and a trailing comment after code reads as none. Both are the price of not parsing, and
  # neither has come up: no template opens a heredoc line with `#`, and the cops forbid
  # nothing about trailing comments. A guard that miscounts is worth having only while it says
  # so.
  def test_no_template_carries_more_than_five_percent_comment
    over = TEMPLATES.filter_map do |path|
      code, comment = measure(path)
      budget = code * BUDGET / 100

      next if comment <= budget

      "#{File.basename(path)}: #{comment} comment lines against a budget of #{budget} " \
        "(#{code} code lines)"
    end

    assert_empty over, <<~WHY
      These templates carry more comment than a shipped file earns.

      Every line here is installed into an application that did not write it, cannot review
      it, and will read it as true long after the law it paraphrases has moved. Put the
      reasoning in the law and leave a clause that names it.
    WHY
  end

  private

  def measure(path)
    lines = File.readlines(path, chomp: true)
    comment = lines.count { |line| line.strip.start_with?("#") && line.strip != PRAGMA }

    [lines.count { |line| !line.strip.empty? && !line.strip.start_with?("#") }, comment]
  end
end
