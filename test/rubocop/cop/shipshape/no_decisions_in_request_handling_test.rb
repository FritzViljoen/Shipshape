# frozen_string_literal: true

require "test_helper"

# Watched to fail, as `a-guard-states-its-limit` requires:
#
# - Making `asks` return `[]` reddens every offence test.
# - Dropping `OUTCOMES` from the skip list reddens the `result.success?` test, which is the
#   one shape the whole rule exists to permit.
# - Making `one_of?` answer true unconditionally reddens the command test.
# - Emptying `WRITES` reddens the write-described-as-a-write test.
class NoDecisionsInRequestHandlingTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoDecisionsInRequestHandling

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "command" => ["app/commands/**/*.rb"],
      },
      "Matrix" => { "request_handling" => ["command"], "command" => [] },
    },
  }.freeze

  CONTROLLER = "app/controllers/bookings_controller.rb"

  def test_a_predicate_on_the_payload_is_a_decision
    found = check(<<~RUBY)
      class BookingsController
        def update
          return redirect_to root_path if @booking.cancelled?
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`@booking` is what this action is about to render"
    assert_includes found.first.message, "asking it `cancelled?`"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class BookingsController
        def update
          render :edit if @booking.overdue?
        end
      end
    RUBY

    assert_includes message, "WHY: The rule now has two owners"
    assert_includes message, "INSTEAD:"
    assert_includes message, "if result.success?"
  end

  # The whole point of the rule: the operation decided, the action places the answer.
  def test_branching_on_an_outcome_is_placing_not_deciding
    assert_empty check(<<~RUBY)
      class BookingsController
        def update
          result = CancelBooking.call(id: params[:id])

          if result.success?
            redirect_to bookings_path
          else
            render :edit, status: :unprocessable_entity
          end
        end
      end
    RUBY
  end

  def test_an_outcome_held_in_an_instance_variable_is_still_an_outcome
    assert_empty check(<<~RUBY)
      class BookingsController
        def update
          @result = CancelBooking.call(id: params[:id])
          redirect_to bookings_path if @result.success?
        end
      end
    RUBY
  end

  # A property of the call being served, not of the domain.
  def test_a_question_about_the_request_is_not_a_domain_decision
    assert_empty check(<<~RUBY)
      class BookingsController
        def show
          render layout: false if request.xhr?
        end
      end
    RUBY
  end

  def test_a_decision_nested_in_a_compound_condition_is_still_a_decision
    found = check(<<~RUBY)
      class BookingsController
        def update
          render :edit if signed_in? && @booking.cancelled?
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  def test_a_case_on_the_payload_is_a_decision
    found = check(<<~RUBY)
      class BookingsController
        def show
          case @booking.state
          when "cancelled" then render :cancelled
          else render :show
          end
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  # The rule is about the file that handles the request, not about branching everywhere.
  def test_a_command_may_branch_all_it_likes
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/commands/cancel_booking.rb", other_cops: LAYOUT)
      class CancelBooking
        def call
          return failure(:already_cancelled) if @booking.cancelled?

          success(@booking)
        end
      end
    RUBY
  end

  # `if @booking.save` is the commonest shape this cop meets in a real controller, and
  # calling it "asking" was inaccurate: it writes, then branches on whether the write worked.
  def test_a_write_is_described_as_a_write_not_a_question
    message = check(<<~RUBY).first.message
      class BookingsController
        def create
          if @booking.save
            redirect_to bookings_path
          else
            render :new
          end
        end
      end
    RUBY

    assert_includes message, "writing through it with `save` and branching on the result"
    refute_includes message, "asking it `save`"
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: CONTROLLER, other_cops: LAYOUT)
  end
end
