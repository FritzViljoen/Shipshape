# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `declaration?` answer false reddens the `every` and `recurring` tests.
# - Making `scheduler?` answer false reddens the Sidekiq and Clockwork tests.
# - Removing `on_casgn` reddens the constant test.
# - Loosening `CRON` to match any string reddens the not-a-cadence test, which is the shape
#   that would fail correct code — a version number is five fields of digits and dots away.
class NothingSchedulesWorkTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NothingSchedulesWork

  def test_a_whenever_block_is_a_cadence_in_code
    found = check(<<~RUBY)
      every 1.day, at: "3:00 am" do
        runner "SettleOverdueInvoices.call"
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`every` declares a cadence in code, and a schedule is a row"
  end

  def test_the_offence_says_why_an_actor_is_the_point
    message = check(<<~RUBY).first.message
      every 1.day do
        runner "Settle.call"
      end
    RUBY

    assert_includes message, "WHY:"
    assert_includes message, "runs under nobody's name"
    assert_includes message, "revoking a person does not stop what they set running"
    assert_includes message, "runs_as_id: treasurer.id"
    # A route, not a class name: the schedule stores a name the outside already relies on.
    assert_includes message, 'path:       "/invoices/settle"'
  end

  def test_a_recurring_declaration_is_the_same_thing
    assert_equal 1, check("recurring every: 1.hour do\n  Settle.call\nend\n").length
  end

  def test_a_scheduler_library_is_a_cadence_in_code
    assert_equal 1, check(<<~RUBY).length
      Sidekiq::Cron::Job.create(name: "settle", cron: "0 3 * * *", class: "SettleJob")
    RUBY
  end

  def test_clockwork_is_named_too
    assert_equal 1, check("Clockwork.every(1.day, 'settle')\n").length
  end

  # The shape a codebase reaches for once the DSL is gone: the cadence moves to a constant and
  # the scheduling happens somewhere the cop was not looking.
  def test_a_cron_expression_in_a_constant_is_a_cadence
    found = check(%(NIGHTLY = "0 3 * * *"\n))

    assert_equal 1, found.length
    assert_includes found.first.message, "`NIGHTLY` declares a cadence in code"
  end

  def test_a_slashed_cron_expression_is_matched
    assert_equal 1, check(%(FREQUENT = "*/15 * * * *"\n)).length
  end

  # **A cop that fails correct code gets disabled.** A version, a path and a sentence are all
  # strings in constants, and none of them is a schedule.
  def test_a_string_that_is_not_a_cadence_is_left_alone
    assert_empty check(<<~RUBY)
      VERSION = "1.2.3"
      PATH = "app/models"
      LABEL = "0 3 * * * is a cron expression"
      DATE = "2026-08-31"
    RUBY
  end

  # `every` on a receiver is somebody else's method — an enumerable, a builder, a test helper.
  def test_every_on_a_receiver_is_not_a_declaration
    assert_empty check("collection.every(1.day) { |x| x }\n")
  end

  # Without a block it is not the DSL. `every` as a plain call is a different method.
  def test_every_without_a_block_is_not_a_declaration
    assert_empty check("total = every(1.day)\n")
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: "config/schedule.rb")
  end
end
