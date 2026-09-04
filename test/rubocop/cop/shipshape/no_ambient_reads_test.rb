# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `CLOCKS` reddens the clock tests; emptying `AMBIENT_CONSTANTS` reddens
# the environment and thread-local tests; making `on_gvar` return early reddens the global test;
# emptying `ZONE_READS` reddens the zone test; emptying `NAIVE_PARSERS` reddens the naive-parse
# tests; emptying `NAIVE_CASTS` reddens the cast tests.
class NoAmbientReadsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoAmbientReads

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "deed" => ["app/deeds/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "Matrix" => { "deed" => [], "request_handling" => ["deed"] },
    },
  }.freeze

  DEED = "app/deeds/expire_holds.rb"

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

  def test_a_naive_parse_is_a_wrong_instant
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.parse(@raw)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "parses a moment against no stated zone"
    assert_includes found.first.message, "lands on a different instant"
  end

  def test_every_naive_parser_in_the_family_is_caught
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          [Time.parse(@raw), Time.strptime(@raw, "%F"), Time.iso8601(@raw),
           DateTime.parse(@raw), DateTime.strptime(@raw, "%F"), DateTime.iso8601(@raw)]
        end
      end
    RUBY

    assert_equal 6, found.length
  end

  def test_date_parse_is_not_governed
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          Date.parse(@raw)
        end
      end
    RUBY
  end

  def test_time_zone_parse_is_the_sanctioned_form
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          Time.zone.parse(@raw)
        end
      end
    RUBY
  end

  def test_time_new_with_no_arguments_is_the_clock
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.new
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "reads the clock"
  end

  def test_time_new_with_naive_arguments_is_a_wrong_instant
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.new(2026, 1, 1, 9, 0, 0)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "parses a moment against no stated zone"
  end

  def test_time_new_naming_its_own_offset_is_not_naive
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          Time.new(2026, 1, 1, 9, 0, 0, in: "+09:00")
        end
      end
    RUBY
  end

  def test_date_time_new_is_not_governed
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          DateTime.new(2026, 1, 1)
        end
      end
    RUBY
  end

  def test_a_bare_cast_preserves_the_instant_but_loses_the_zone
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          @moment.to_time
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "casts to a bare moment with no zone attached"
    assert_includes found.first.message, "instant it names is unchanged"
  end

  def test_to_datetime_is_the_same_cast
    assert_equal 1, check(<<~RUBY).length
      class ExpireHolds
        def call
          @moment.to_datetime
        end
      end
    RUBY
  end

  def test_time_at_is_a_cast_not_a_wrong_instant
    found = check(<<~RUBY)
      class ExpireHolds
        def call
          Time.at(@epoch)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "casts to a bare moment with no zone attached"
  end

  def test_time_zone_at_is_the_sanctioned_form
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          Time.zone.at(@epoch)
        end
      end
    RUBY
  end

  def test_time_at_naming_its_own_offset_is_not_naive
    assert_empty check(<<~RUBY)
      class ExpireHolds
        def call
          Time.at(@epoch, in: "+09:00")
        end
      end
    RUBY
  end

  # The edge is where parsing belongs, and `NoInlineParamParse` already covers it there — this
  # cop is not scoped to `request_handling`, so the two never report the same call twice.
  def test_request_handling_may_parse_the_zone_it_asked_for
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/controllers/holds_controller.rb", other_cops: LAYOUT)
      class HoldsController
        def show
          Time.parse(params[:at])
        end
      end
    RUBY
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
    offences(source, cop_class: COP, path: DEED, other_cops: LAYOUT)
  end
end
