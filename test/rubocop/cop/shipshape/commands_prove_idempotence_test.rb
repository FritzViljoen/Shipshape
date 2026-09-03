# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `tests_for` answer the whole test list reddens the missing-claim tests;
# making the claim check pass unconditionally reddens all of them; changing `CLAIM` without
# changing the fixtures reddens the accepted tests, which is the pair that matters: the phrase IS
# the act being required, so the cop must key on it. **It checks that the claim was written, never
class CommandsProveIdempotenceTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CommandsProveIdempotence

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "query" => ["app/queries/**/*.rb"],
      },
      "Matrix" => { "command" => [], "query" => [] },
    },
  }.freeze

  COMMAND = "app/commands/settle_invoice.rb"
  SOURCE = "class SettleInvoice < Command\n  def call; end\nend\n"

  def test_a_command_with_no_test_at_all_is_refused
    found = check({})

    assert_equal 1, found.length
    assert_includes found.first.message, "no test file names it"
  end

  def test_a_command_whose_test_makes_no_claim_is_refused
    found = check("test/commands/settle_invoice_test.rb" => "class X\n  def test_it; end\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "its test does not say"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check({}).first.message

    assert_includes message, "WHY: `tell-dont-ask` already obliges it"
    assert_includes message, "a queue retries"
    assert_includes message, "INSTEAD:"
    assert_includes message, "Idempotent: the unique index"
  end

  def test_a_written_claim_settles_it
    assert_empty check("test/commands/settle_invoice_test.rb" =>
                       "# Idempotent: settled_at guards the second call.\nclass X; end\n")
  end

  # A bare marker settled nothing about how the operation is safe to repeat.
  def test_the_marker_alone_does_not_settle_it
    found = check("test/commands/settle_invoice_test.rb" => "# Idempotent:\nclass X; end\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "its test does not say"
  end

  def test_the_marker_must_lead_a_comment_not_sit_inside_one
    found = check("test/commands/settle_invoice_test.rb" =>
                  "# See Idempotent: settled_at guards the second call.\nclass X; end\n")

    assert_equal 1, found.length
  end

  def test_the_marker_must_be_a_comment_not_a_string
    found = check("test/commands/settle_invoice_test.rb" =>
                  %(X = "Idempotent: settled_at guards the second call."\n))

    assert_equal 1, found.length
  end

  def test_the_test_may_live_anywhere_under_a_declared_root
    %w[test/settle_invoice_test.rb spec/commands/settle_invoice_spec.rb
       test/app/commands/settle_invoice_test.rb].each do |path|
      assert_empty check(path => "# Idempotent: settled_at guards it.\n"), path
    end
  end

  def test_another_commands_test_does_not_count
    assert_equal 1, check("test/commands/other_test.rb" => "# Idempotent: whatever.\n").length
  end

  # `each_ancestor(:class, :module)` skipped every command declared inside a module, which in
  # most applications is most of them.
  def test_a_command_inside_a_module_is_not_skipped
    found = offences("module Billing\n  class SettleInvoice < Command\n    def call; end\n  end\nend\n",
                     cop_class: COP, path: "app/commands/billing/settle_invoice.rb",
                     files: {}, other_cops: LAYOUT)

    assert_equal 1, found.length
  end

  def test_a_namespaced_command_is_settled_by_its_own_test
    files = { "test/commands/billing/settle_invoice_test.rb" => "# Idempotent: settled_at guards it.\n" }

    assert_empty offences("module Billing\n  class SettleInvoice < Command\n  end\nend\n",
                          cop_class: COP, path: "app/commands/billing/settle_invoice.rb",
                          files: files, other_cops: LAYOUT)
  end

  def test_a_query_is_not_this_cops_business
    assert_empty offences("class ListPeople < Query\nend\n", cop_class: COP,
                          path: "app/queries/list_people.rb", other_cops: LAYOUT)
  end

  # **The stated limit, pinned.** The claim is a sentence, not a proof, and a false one passes.
  def test_a_claim_that_is_untrue_passes_and_that_is_the_limit
    assert_empty check("test/commands/settle_invoice_test.rb" =>
                       "# Idempotent: nothing whatsoever makes this true.\nclass X; end\n")
  end

  private

  def check(files)
    offences(SOURCE, cop_class: COP, path: COMMAND, files: files, other_cops: LAYOUT)
  end
end
