# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `guarded?` answer true reddens the unguarded-keyword test; making
# `check_argument` return early on `:arg` reddens the positional test; emptying `UNNAMED` reddens
# the splat tests; emptying `NAIVE_MOMENTS` reddens the bare-`Time` and bare-`DateTime` tests;
# making `on_def` skip the `initialize` check reddens nothing on its own, which is
# why there is a test that a guard-free `call` is not this cop's business.
class TypedArgumentsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::TypedArguments

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "Matrix" => { "command" => ["shape"], "shape" => [] },
    },
  }.freeze

  COMMAND = "app/commands/settle_invoice.rb"

  def test_an_unasserted_keyword_is_an_offence
    found = check(<<~RUBY)
      class SettleInvoice
        def initialize(settled_on:)
          @settled_on = settled_on
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`settled_on:` is stored without being asserted"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class SettleInvoice
        def initialize(settled_on:)
          @settled_on = settled_on
        end
      end
    RUBY

    assert_includes message, "WHY: The boundary is the point"
    assert_includes message, "INSTEAD:"
    assert_includes message, "@settled_on = typed(settled_on, Date)"
  end

  def test_a_guarded_keyword_is_the_shape
    assert_empty check(<<~RUBY)
      class SettleInvoice
        def initialize(invoice_id:, settled_on:, note: nil)
          @invoice_id = typed(invoice_id, Integer)
          @settled_on = typed(settled_on, Date)
          @note = typed(note, String, allow_nil: true)
        end
      end
    RUBY
  end

  def test_the_collection_guards_count
    assert_empty check(<<~RUBY)
      class SettleInvoice
        def initialize(lines:, rates:)
          @lines = typed_array(lines, Line)
          @rates = typed_hash(rates, Symbol, BigDecimal)
        end
      end
    RUBY
  end

  def test_a_positional_parameter_is_its_own_offence
    found = check(<<~RUBY)
      class SettleInvoice
        def initialize(invoice_id)
          @invoice_id = invoice_id
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "is a positional parameter, not a named keyword"
  end

  def test_a_keyword_splat_swallows_the_callers_keywords
    found = check(<<~RUBY)
      class SettleInvoice
        def initialize(**options)
          @options = options
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "silently accepts the caller's keywords as one Hash"
  end

  def test_a_positional_splat_is_its_own_offence
    assert_equal 1, check(<<~RUBY).length
      class SettleInvoice
        def initialize(*args)
          @args = args
        end
      end
    RUBY
  end

  def test_a_block_argument_is_not_an_offence
    assert_empty check(<<~RUBY)
      class SettleInvoice
        def initialize(invoice_id:, &block)
          @invoice_id = typed(invoice_id, Integer)
          @block = block
        end
      end
    RUBY
  end

  # This cop catches the declared type, at lint time, before anything runs. `typed`
  # catches the value too, at runtime — but only on the line that actually executes.
  def test_a_keyword_declared_as_a_bare_time_names_no_zone
    found = check(<<~RUBY)
      class SettleInvoice
        def initialize(settled_at:)
          @settled_at = typed(settled_at, Time)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`Time` names no zone"
    assert_includes found.first.message, "WHY: A bare `Time` carries whatever offset"
    assert_includes found.first.message, "typed(now, ActiveSupport::TimeWithZone)"
  end

  def test_datetime_is_the_same_offence
    found = check(<<~RUBY)
      class SettleInvoice
        def initialize(settled_at:)
          @settled_at = typed(settled_at, DateTime)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`DateTime` names no zone"
  end

  def test_a_zoned_moment_and_a_calendar_date_are_the_shape
    assert_empty check(<<~RUBY)
      class SettleInvoice
        def initialize(settled_at:, departs_on:, at:)
          @settled_at = typed(settled_at, ActiveSupport::TimeWithZone)
          @departs_on = typed(departs_on, Date)
          @at = typed(at, ::ActiveSupport::TimeWithZone)
        end
      end
    RUBY
  end

  # The keyword is guarded, so the unguarded-keyword rule has nothing to say — and the type it
  # names is still wrong. Both had to be reported from one walk.
  def test_a_naive_moment_inside_a_collection_guard_is_caught
    assert_equal 1, check(<<~RUBY).length
      class SettleInvoice
        def initialize(stamps:)
          @stamps = typed_array(stamps, Time)
        end
      end
    RUBY
  end

  def test_a_cbase_time_is_the_same_offence
    assert_equal 1, check(<<~RUBY).length
      class SettleInvoice
        def initialize(settled_at:)
          @settled_at = typed(settled_at, ::Time)
        end
      end
    RUBY
  end

  # The rule is about arguments arriving, not about every method.
  def test_only_the_initializer_is_checked
    assert_empty check(<<~RUBY)
      class SettleInvoice
        def call(anything, **rest)
          anything
        end
      end
    RUBY
  end

  def test_a_shape_is_outside_the_default_scope
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/shapes/invoice.rb", other_cops: LAYOUT)
      class Invoice
        def initialize(number:)
          @number = number
        end
      end
    RUBY
  end

  # **A shape holds a shape and validates that shape**, so its initializer is asserted like a
  # door's. This was left out until the kind was audited for: a shape could take a positional,
  # a `**rest`, or an unguarded keyword and nothing objected — in the one class whose entire
  # job is to be a validated value.
  SHAPE = "app/shapes/place.rb"

  SHAPE_KINDS = { "Kinds" => %w[command shape] }.freeze

  def test_a_shape_asserts_its_keywords_too
    found = check(shape("def initialize(code:)\n    @code = code\n  end"), SHAPE, SHAPE_KINDS)

    assert_equal 1, found.length
  end

  def test_a_shape_may_not_take_a_positional_or_a_splat
    positional = check(shape("def initialize(code)\n    @code = code\n  end"), SHAPE, SHAPE_KINDS)
    splat = check(shape("def initialize(**o)\n    @o = o\n  end"), SHAPE, SHAPE_KINDS)

    assert_equal 1, positional.length
    assert_equal 1, splat.length
  end

  def test_a_guarded_shape_is_the_shape
    assert_empty check(shape("def initialize(code:)\n    @code = typed(code, String)\n  end"),
                       SHAPE, SHAPE_KINDS)
  end

  # A value with no state is legitimate, so a missing initializer is not reported.
  def test_a_shape_with_no_initializer_is_left_alone
    assert_empty check(shape("def code\n    @code\n  end"), SHAPE, SHAPE_KINDS)
  end

  private

  def shape(body)
    "class Place < Shape\n  #{body}\nend\n"
  end

  def check(source, path = COMMAND, config = {})
    offences(source, cop_class: COP, cop_config: config, path: path, other_cops: LAYOUT)
  end
end
