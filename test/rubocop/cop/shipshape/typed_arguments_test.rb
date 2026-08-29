# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `guarded?` answer true reddens the unguarded-keyword test.
# - Making `check_argument` return early on `:arg` reddens the positional test.
# - Emptying `UNNAMED` reddens the splat tests.
# - Making `on_def` skip the `initialize` check reddens nothing on its own, which is why
#   there is a test that a guard-free `call` is not this cop's business.
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

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, other_cops: LAYOUT)
  end
end
