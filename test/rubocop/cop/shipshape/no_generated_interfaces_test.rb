# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `DEFINERS` reddens the define_method test; emptying `EVALUATORS`
# reddens the string-eval test; emptying `DISPATCH` reddens the method_missing test; making
# `one_of?` answer true unconditionally reddens the request-handling test.
class NoGeneratedInterfacesTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoGeneratedInterfaces

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "shape" => ["app/shapes/**/*.rb"],
        "request_handling" => ["app/controllers/**/*_controller.rb"],
      },
      "Matrix" => { "shape" => [], "request_handling" => ["shape"] },
    },
  }.freeze

  SHAPE = "app/shapes/invoice.rb"

  def test_defining_methods_from_data_is_an_offence
    found = check(<<~RUBY)
      class Invoice
        FIELDS.each { |field| define_method(field) { @row[field] } }
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "writes methods a reader would otherwise grep for"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class Invoice
        FIELDS.each { |field| define_method(field) { @row[field] } }
      end
    RUBY

    assert_includes message, "WHY: The method exists at runtime and not in the source"
    assert_includes message, "INSTEAD:"
    assert_includes message, "attr_reader :number, :issued_on"
  end

  def test_evaluating_a_string_as_code_is_an_offence
    found = check(<<~'RUBY')
      class Invoice
        class_eval "def number; @number; end"
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "builds code out of a string"
  end

  def test_missing_method_dispatch_is_an_offence
    found = check(<<~RUBY)
      class Invoice
        def method_missing(name, *args)
          @row[name]
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "answers for methods that were never written"
  end

  def test_written_out_methods_are_the_shape
    assert_empty check(<<~RUBY)
      class Invoice
        def initialize(number:, issued_on:)
          @number = typed(number, String)
          @issued_on = typed(issued_on, Date)
        end

        attr_reader :number, :issued_on
      end
    RUBY
  end

  # The framework's own conventions are exempt, and this is the line the law draws.
  def test_a_public_framework_macro_is_not_this_cops_business
    assert_empty check(<<~RUBY)
      class Invoice
        delegate :name, to: :supplier
        validates :number, presence: true
      end
    RUBY
  end

  def test_request_handling_is_outside_the_default_scope
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/controllers/invoices_controller.rb", other_cops: LAYOUT)
      class InvoicesController
        FIELDS.each { |field| define_method(field) { params[field] } }
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: SHAPE, other_cops: LAYOUT)
  end
end
