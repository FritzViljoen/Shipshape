# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `flattened_from` answer nil reddens the flattening tests; setting
# `minimum_fields` to 1 reddens the single-prefixed-keyword test, which is the false positive the
# heuristic is deliberately tuned to avoid.
class ShapeIsComposedTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::ShapeIsComposed

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "shape" => ["app/shapes/**/*.rb"],
        "command" => ["app/commands/**/*.rb"],
      },
      "Matrix" => { "shape" => [], "command" => ["shape"] },
    },
  }.freeze

  SHAPE = "app/shapes/booking.rb"

  def test_copied_fields_are_flattening
    found = check(<<~RUBY)
      class Booking
        def initialize(reference:, supplier_name:, supplier_email:)
          @reference = reference
        end
      end
    RUBY

    assert_equal 2, found.length
    assert_includes found.first.message, "`supplier_name:` copies a field off `Supplier`"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class Booking
        def initialize(supplier_name:, supplier_email:)
          @supplier_name = supplier_name
        end
      end
    RUBY

    assert_includes message, "WHY: A flattened field is the first column of the next god object"
    assert_includes message, "INSTEAD:"
    assert_includes message, "@supplier = typed(supplier, Supplier)"
  end

  def test_holding_the_other_object_is_the_shape
    assert_empty check(<<~RUBY)
      class Booking
        def initialize(reference:, supplier:)
          @reference = typed(reference, String)
          @supplier = typed(supplier, Supplier)
        end
      end
    RUBY
  end

  # The heuristic's deliberate blind spot: one prefixed keyword is just a name.
  def test_a_single_prefixed_keyword_is_just_a_name
    assert_empty check(<<~RUBY)
      class Booking
        def initialize(person_id:, reference:)
          @person_id = person_id
        end
      end
    RUBY
  end

  def test_an_unprefixed_keyword_is_never_flattening
    assert_empty check(<<~RUBY)
      class Booking
        def initialize(reference:, total:)
          @reference = reference
        end
      end
    RUBY
  end

  def test_a_command_is_outside_the_shape_tree
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/commands/create_booking.rb", other_cops: LAYOUT)
      class CreateBooking
        def initialize(supplier_name:, supplier_email:)
          @supplier_name = supplier_name
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: SHAPE, other_cops: LAYOUT)
  end
end
