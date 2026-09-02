# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `extends_the_sweep?` answer true reddens both offence tests, and
# `inherits_a_governed_class?` answer false reddens the class-below-a-base test.
class PresentationHoldsNoRecordsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::PresentationHoldsNoRecords

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "shape" => ["app/shapes/**/*.rb"],
                   "view_component" => ["app/view_components/**/*.rb"],
                   "record" => ["app/models/**/*.rb"] },
      "Matrix" => { "shape" => [], "view_component" => %w[shape], "record" => [] },
    },
  }.freeze

  SHAPE = "app/shapes/basket.rb"

  def test_a_shape_nothing_sweeps_is_an_offence
    found = check("class Basket\n  def initialize(lines:)\n    @lines = lines\n  end\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "Nothing sweeps `Basket`"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("class Basket\nend\n").first.message

    assert_includes message, "WHY: A record is only allowed in a write or a read"
    assert_includes message, "INSTEAD:"
    assert_includes message, "extend HoldsNoRecords"
  end

  def test_a_base_that_does_the_asking_itself_is_the_shape
    assert_empty check("class Shape\n  extend HoldsNoRecords\nend\n")
  end

  # The sweep is inherited, so a class below a swept base declares nothing.
  def test_a_class_below_a_governed_base_is_swept_by_it
    assert_empty offences("class Basket < Money\nend\n", cop_class: COP, path: SHAPE,
                          other_cops: LAYOUT,
                          files: { "app/shapes/money.rb" => "class Money\n  extend HoldsNoRecords\nend\n" })
  end

  # Any component library, without this cop naming one: the kind is declared by path.
  def test_a_component_on_a_library_this_cop_never_heard_of
    found = offences("class CardComponent < Phlex::HTML\nend\n", cop_class: COP,
                     path: "app/view_components/card_component.rb", other_cops: LAYOUT)

    assert_equal 1, found.length, "the kind is the subject, not a list of base classes"
  end

  def test_a_record_is_not_this_cop_s_business
    assert_empty offences("class PersonRecord < ApplicationRecord\nend\n", cop_class: COP,
                          path: "app/models/person_record.rb", other_cops: LAYOUT)
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: SHAPE, other_cops: LAYOUT)
  end
end
