# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `CLOCKS` reddens the clock tests; emptying `AMBIENT_CONSTANTS` reddens
# the environment and thread-local tests; making `on_gvar` return early reddens the global test;
# emptying `ZONE_READS` reddens the zone tests; emptying `NAIVE_BUILDERS` reddens the builder
# tests; emptying `NAIVE_CASTS` reddens the cast test; and restoring the old blanket exemption —
# `reported_as_a_clock?` answering true for any chain — reddens the `Time.zone.parse` test while
# the `Time.zone.now` count test stays green, which is the pair that says the two are not one rule.
class NoAmbientReadsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoAmbientReads

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "Matrix" => { "command" => [], "request_handling" => ["command"] },
    },
  }.freeze

  COMMAND = "app/commands/expire_holds.rb"

  def test_reading_the_clock_is_an_ambient_read
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          BookingRecord.where("starts_at > ?", Time.now)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`Time.now` reads the clock"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class ExpireHolds
        def call
          Date.today
        end
      end
    RUBY

    assert_includes message, "WHY: The current time is a dependency that is not on the call path"
    assert_includes message, "INSTEAD:"
    assert_includes message, "def initialize(now:)"
  end

  def test_every_clock_in_the_family_is_caught
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          [Time.now, Time.current, Date.today, Date.current, DateTime.now, Time.zone.now]
        end
      end
    RUBY

    assert_equal 6, found.length
  end

  def test_the_environment_is_an_ambient_read
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          ENV.fetch("RATE")
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "request-scoped or process-wide state"
  end

  def test_a_thread_local_is_an_ambient_read
    assert_equal 1, check(<<~RUBY).length
      class ExpireHolds
        def call
          Thread.current[:tenant]
        end
      end
    RUBY
  end

  def test_a_global_is_an_ambient_read
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          $current_tenant
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`$current_tenant` reads a global"
  end

  def test_the_ambient_zone_is_an_ambient_read
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.zone
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "reads the ambient zone"
  end

  # The clock is not the only ambient read in the family: parsing a string with `Time.parse`
  # applies the process's zone, so the same input is a different instant per machine.
  def test_parsing_a_time_takes_its_zone_from_the_process
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.parse(@raw)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`Time.parse(@raw)` builds a moment in whatever zone"
    assert_includes found.first.message, "WHY: The zone is a dependency that is not on the call path"
  end

  def test_every_naive_builder_in_the_family_is_caught
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          [Time.parse(@raw), Time.strptime(@raw, "%F"), Time.iso8601(@raw), Time.at(@epoch),
           Time.new(2026, 1, 1), DateTime.parse(@raw), DateTime.strptime(@raw, "%F"),
           DateTime.iso8601(@raw)]
        end
      end
    RUBY

    assert_equal 8, found.length
  end

  # A calendar date carries no zone by design, so building one reads nothing ambient. `Date.new`
  # and `DateTime.new` are plain constructors with a stated offset and stay legal too.
  def test_a_calendar_date_is_left_alone
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          [Date.parse(@raw), Date.new(2026, 1, 1), DateTime.new(2026, 1, 1)]
        end
      end
    RUBY
  end

  def test_a_bare_cast_is_an_ambient_read
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          [@raw.to_time, @raw.to_datetime]
        end
      end
    RUBY

    assert_equal 2, found.length
    assert_includes found.first.message, "builds a moment in whatever zone"
  end

  # `to_date` is left alone for the same reason `Date.parse` is.
  def test_a_cast_to_a_calendar_date_is_left_alone
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          @raw.to_date
        end
      end
    RUBY
  end

  # The blanket exemption that kept `Time.zone.now` from being reported twice also silenced
  # this, and nothing else reports it — the zone it applies is still one nobody stated.
  def test_parsing_through_the_ambient_zone_is_still_an_ambient_read
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.zone.parse(@raw)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`Time.zone` reads the ambient zone"
  end

  def test_a_moment_handed_in_is_the_shape
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def initialize(now:)
          @now = typed(now, ActiveSupport::TimeWithZone)
        end

        def call
          BookingRecord.where("starts_at > ?", @now)
        end
      end
    RUBY
  end

  # The edge is where the clock is read. That is the whole point of the rule.
  def test_request_handling_may_read_the_clock
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/controllers/holds_controller.rb", other_cops: LAYOUT)
      class HoldsController
        def destroy
          ExpireHolds.call(now: Time.zone.now)
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, other_cops: LAYOUT)
  end
end
