# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `CLOCKS` reddens the clock tests; emptying `AMBIENT_CONSTANTS` reddens
# the environment and thread-local tests; making `on_gvar` return early reddens the global test;
# emptying `ZONE_READS` reddens the zone test.
class NoAmbientReadsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoAmbientReads

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "write" => ["app/writes/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "Matrix" => { "write" => [], "request_handling" => ["write"] },
    },
  }.freeze

  WRITE = "app/writes/expire_holds.rb"

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
    offences(source, cop_class: COP, path: WRITE, other_cops: LAYOUT)
  end
end
