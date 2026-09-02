# frozen_string_literal: true

require "test_helper"

# Watched to fail: adding a name to `PERMITTED` reddens the only-two tests, and emptying it
# reddens the `success?` and `present?` tests — the pair that matters. Making `asks` return
# `[]` reddens the ivar test; emptying `WRITES` reddens the write-described-as-a-write test.
class NoDecisionsInRequestHandlingTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoDecisionsInRequestHandling

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "write" => ["app/writes/**/*.rb"],
      },
      "Matrix" => { "request_handling" => ["write"], "write" => [] },
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
  # Format dispatch has one spelling, and it is not a conditional. `respond_to` names each
  # outcome and its response, which is what this layer is for.
  def test_respond_to_is_how_a_format_is_chosen
    assert_empty check(<<~RUBY)
      class BookingsController
        def show
          respond_to do |format|
            format.html { render :show }
            format.json { render json: @booking }
          end
        end
      end
    RUBY
  end

  def test_asking_the_request_is_still_a_branch
    found = check(<<~RUBY)
      class BookingsController
        def show
          render layout: false if request.xhr?
        end
      end
    RUBY

    assert_equal 1, found.length,
                 "`respond_to` is the spelling for this, and it names both outcomes"
    assert_includes found.first.message, "tests `success?` and `present?`, and nothing else"
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
  def test_a_write_may_branch_all_it_likes
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/writes/cancel_booking.rb", other_cops: LAYOUT)
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

  # `present?` is correct across all three answers a read may give: `nil` and `[]` are absent,
  # a shape and an array of shapes are present.
  def test_present_asks_whether_a_read_found_anything
    assert_empty check(<<~RUBY)
      class BookingsController
        def show
          if FindBooking.call(id: 1).present?
            render :show
          else
            redirect_to "/"
          end
        end
      end
    RUBY
  end

  # A read may answer nothing, so the caller has to ask whether it found any — and `present?`
  # is the one spelling. Bare truthiness and its cousins say the same thing in other words.
  def test_only_present_asks_whether_a_read_found_anything
    %w[booking booking.nil? booking.any?].each do |condition|
      found = check(<<~RUBY)
        class BookingsController
          def show
            booking = FindBooking.call(id: 1)

            if #{condition}
              render :show
            else
              redirect_to "/"
            end
          end
        end
      RUBY

      assert_equal 1, found.length, condition
      assert_includes found.first.message, "tests `success?` and `present?`, and nothing else"
    end
  end

  # The receiver is not the test. Walking every node made this an offence, and it is the shape
  # the whole rule exists to permit.
  def test_a_write_result_is_still_the_shape
    assert_empty check(<<~RUBY)
      class BookingsController
        def update
          result = CancelBooking.call(id: 1)

          if result.success?
            redirect_to "/"
          else
            render :edit
          end
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: CONTROLLER, other_cops: LAYOUT)
  end
end
