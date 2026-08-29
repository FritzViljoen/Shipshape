# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Emptying `CASTS` reddens every offence test.
# - Making `untrusted?` answer true reddens the already-a-number test — the false positive
#   the law's limit is written about, and the reason the cop is deliberately narrow.
class NoSilentCoercionTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoSilentCoercion

  PATH = "app/controllers/bookings_controller.rb"

  def test_a_cast_on_a_parameter_is_an_offence
    found = check(<<~RUBY)
      class BookingsController
        def index
          params[:page].to_i
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "turns whatever arrived into a number that cannot fail"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class BookingsController
        def index
          params[:page].to_i
        end
      end
    RUBY

    assert_includes message, 'WHY: `"banana".to_i` is 0'
    assert_includes message, "INSTEAD:"
    assert_includes message, "integer_param!(:page)"
  end

  def test_the_example_names_the_parser_for_the_cast
    message = check(<<~RUBY).first.message
      class BookingsController
        def index
          params[:amount].to_f
        end
      end
    RUBY

    assert_includes message, "decimal_param!(:amount)"
  end

  def test_every_untrusted_source_counts
    found = check(<<~RUBY)
      class BookingsController
        def index
          [params[:a].to_i, session[:b].to_i, cookies[:c].to_i, request.headers["d"].to_i]
        end
      end
    RUBY

    assert_equal 4, found.length
  end

  def test_a_named_parser_is_the_shape
    assert_empty check(<<~RUBY)
      class BookingsController
        def index
          integer_param(:page, default: 1)
        end
      end
    RUBY
  end

  # The limit, pinned so nobody reads a green run as covering more than it does: a value
  # that passed through a local first is invisible, deliberately.
  def test_a_cast_on_a_local_is_not_covered
    assert_empty check(<<~RUBY)
      class BookingsController
        def index
          page = params[:page]
          page.to_i
        end
      end
    RUBY
  end

  def test_a_cast_on_something_already_asserted_is_not_covered
    assert_empty check(<<~RUBY)
      class BookingsController
        def index
          @booking.head_count.to_i
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
