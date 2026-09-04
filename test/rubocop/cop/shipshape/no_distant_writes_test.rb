# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `on_gvasgn` return early reddens the global test; making `on_cvasgn`
# return early reddens the class-variable test; making `on_send` return early reddens the constant-
# mutation tests; making `one_of?` answer true unconditionally reddens the request-handling test;
# emptying `subscription_call?` reddens the subscribe/instrument/attached-callback tests.
class NoDistantWritesTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoDistantWrites

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "deed" => ["app/deeds/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "Matrix" => { "deed" => [], "request_handling" => ["deed"] },
    },
  }.freeze

  DEED = "app/deeds/switch_tenant.rb"

  def test_assigning_a_global_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          $current_tenant = @tenant
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`$current_tenant` is a global"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class SwitchTenant
        def call
          $current_tenant = @tenant
        end
      end
    RUBY

    assert_includes message, "WHY: This is action at a distance"
    assert_includes message, "INSTEAD:"
    assert_includes message, "success(Session.new(tenant: @tenant))"
  end

  def test_a_class_variable_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          @@cache = @tenant
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "shared with every subclass"
  end

  def test_mutating_a_constant_in_place_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          Settings::CACHE[:rate] = @rate
          REGISTRY << @tenant
        end
      end
    RUBY

    assert_equal 2, found.length
  end

  # The law's own example — held for regression, not because the shape was ever missed.
  def test_appending_onto_a_constant_held_subscriber_list_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          Subscribers << self
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`Subscribers` is a constant"
  end

  def test_subscribing_to_notifications_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          ActiveSupport::Notifications.subscribe("tenant.switched") { |*args| log(args) }
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`ActiveSupport::Notifications.subscribe` hands a handler"
  end

  def test_instrumenting_notifications_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          ActiveSupport::Notifications.instrument("tenant.switched") { @tenant }
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "resolved by lookup at runtime"
  end

  # Registering an observer is `.observers=`, an assignment on a constant receiver — already
  # the shape above catches, so no new matcher was needed for it.
  def test_registering_an_active_record_observer_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          ActiveRecord::Base.observers = [:audit_observer]
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`ActiveRecord::Base` is a constant"
  end

  # `NoLifecycleCallbacks` catches the bare form, written inside the record. This is the
  # form its own Guard's limit hands off: the same hook, attached from outside it.
  def test_attaching_a_callback_from_outside_the_record_is_a_distant_write
    found = check(<<~RUBY)
      class SwitchTenant
        def call
          BookingRecord.after_commit { notify }
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`BookingRecord.after_commit` hands a handler"
  end

  # A domain method that happens to share a name with the Notifications DSL is not pub/sub,
  # and the receiver restriction is what tells them apart.
  def test_a_subscribe_call_on_an_unrelated_constant_is_not_flagged
    assert_empty check(<<~RUBY)
      class SwitchTenant
        def call
          Newsletter.subscribe(@tenant)
        end
      end
    RUBY
  end

  def test_a_class_level_attribute_write_is_a_distant_write
    assert_equal 1, check(<<~RUBY).length
      class SwitchTenant
        def call
          Config.rate = @rate
        end
      end
    RUBY
  end

  def test_writing_to_what_was_handed_in_is_the_shape
    assert_empty check(<<~RUBY)
      class SwitchTenant
        def call
          @totals[:rate] = @rate
          @session.tenant = @tenant
          success(@session)
        end
      end
    RUBY
  end

  # Building a record is not a distant write — it is the work.
  def test_calling_a_record_is_not_a_write_off_the_call_path
    assert_empty check(<<~RUBY)
      class SwitchTenant
        def call
          TenantRecord.find(@id).update!(active: true)
        end
      end
    RUBY
  end

  def test_request_handling_is_outside_the_cops_scope
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/controllers/tenants_controller.rb", other_cops: LAYOUT)
      class TenantsController
        def create
          $current_tenant = params[:id]
        end
      end
    RUBY
  end

  # Ruby spells comparison with a trailing `=` too. Reporting these was the cop firing on
  # every guard clause in the codebase.
  def test_comparing_against_a_constant_is_not_a_write
    assert_empty check(<<~RUBY)
      class SwitchTenant
        def call
          return failure(:held) if Booking::HELD == @state
          return failure(:sold) if Booking::SOLD != @state
          return failure(:free) if Money::ZERO <= @amount
          success(@state)
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: DEED, other_cops: LAYOUT)
  end
end
