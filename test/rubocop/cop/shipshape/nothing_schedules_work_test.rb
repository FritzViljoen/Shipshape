# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `declaration?` answer false reddens the `every` and `recurring` tests.
# - Making `scheduler?` answer false reddens the Sidekiq and Clockwork tests.
# - Adding any constant-string clause back reddens the cron-in-a-constant test, which is the
#   shape that would fail correct code: the value the offence's own `instead:` recommends.
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

  # **The constant clause was removed rather than narrowed.** `NIGHTLY = "0 3 * * *"` is the
  # value the offence's own `instead:` hands to `CreateSchedule`, so following the fix earned
  # the offence — and a guard that fails its own advice is one nobody keeps.
  def test_a_cron_string_in_a_constant_is_not_an_offence
    assert_empty check(<<~RUBY)
      NIGHTLY = "0 3 * * *"
      FREQUENT = "*/15 * * * *"
      GRID = "1 2 3 4 5"
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
