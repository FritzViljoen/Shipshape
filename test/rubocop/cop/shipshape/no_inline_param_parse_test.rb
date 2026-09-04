# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `PARSERS` reddens the parser tests; emptying `CONVERSIONS` reddens the
# raising-conversion test; making `reads_params?` answer true reddens the no-parameter test, which
# is the one that holds the cop to input rather than to parsing in general.
class NoInlineParamParseTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoInlineParamParse

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "deed" => ["app/deeds/**/*.rb"],
      },
      "Matrix" => { "request_handling" => ["deed"], "deed" => [] },
    },
  }.freeze

  CONTROLLER = "app/controllers/bookings_controller.rb"

  def test_parsing_a_parameter_inline_is_an_offence
    found = check(<<~RUBY)
      class BookingsController
        def create
          Date.parse(params[:on])
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "parses a request parameter inline"
  end

  def test_the_offence_carries_the_reason_and_a_matching_example
    message = check(<<~RUBY).first.message
      class BookingsController
        def create
          Date.parse(params[:on])
        end
      end
    RUBY

    assert_includes message, "WHY: A parameter is a string somebody typed"
    assert_includes message, "INSTEAD:"
    assert_includes message, "date_param!(:on, time_zone: time_zone_param!(:zone))"
  end

  def test_the_example_names_the_parser_for_the_type_being_parsed
    message = check(<<~RUBY).first.message
      class BookingsController
        def create
          BigDecimal(params[:amount])
        end
      end
    RUBY

    assert_includes message, "decimal_param!(:amount)"
  end

  def test_a_raising_conversion_is_an_offence
    assert_equal 1, check(<<~RUBY).length
      class BookingsController
        def show
          Integer(params[:id])
        end
      end
    RUBY
  end

  def test_a_parameter_reached_at_any_depth_counts
    assert_equal 1, check(<<~RUBY).length
      class BookingsController
        def create
          Time.strptime(params.fetch(:at), "%H:%M")
        end
      end
    RUBY
  end

  # The cop is about request input, not about parsing.
  def test_parsing_something_that_is_not_a_parameter_is_not_this_cops_business
    assert_empty check(<<~RUBY)
      class BookingsController
        def create
          Date.parse(@supplier.feed_date)
        end
      end
    RUBY
  end

  def test_the_named_parsers_are_the_shape
    assert_empty check(<<~RUBY)
      class BookingsController
        def create
          CreateBooking.call(
            on: date_param!(:on, time_zone: time_zone_param!(:zone)),
            id: integer_param!(:id),
          )
        end
      end
    RUBY
  end

  # `to_i` cannot raise, so it is silent coercion and a different cop holds it.
  def test_a_non_raising_cast_is_left_to_the_coercion_cop
    assert_empty check(<<~RUBY)
      class BookingsController
        def show
          params[:id].to_i
        end
      end
    RUBY
  end

  def test_a_deed_is_outside_the_seam
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/deeds/create_booking.rb", other_cops: LAYOUT)
      class CreateBooking
        def call
          Date.parse(params[:on])
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: CONTROLLER, other_cops: LAYOUT)
  end
end
