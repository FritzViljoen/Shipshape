# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `extends_the_sweep?` answer true reddens both offence tests, and false
# reddens the accepted ones — including the file shipshape itself writes.
class PresentationHoldsNoRecordsTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::PresentationHoldsNoRecords

  PATH = "app/components/card_component.rb"

  def test_a_base_that_does_not_extend_the_sweep_is_an_offence
    found = check(<<~RUBY)
      class ApplicationComponent < ViewComponent::Base
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message,
                    "`ApplicationComponent` inherits `ViewComponent::Base` and does not extend"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("class ApplicationComponent < ViewComponent::Base\nend\n").first.message

    assert_includes message, "WHY: A record handed to a component can lazily load"
    assert_includes message, "INSTEAD:"
    assert_includes message, "extend HoldsNoRecords"
  end

  def test_the_generated_base_is_the_shape
    assert_empty check(<<~RUBY)
      class ApplicationViewComponent < ViewComponent::Base
        include TypedArguments

        extend HoldsNoRecords
      end
    RUBY
  end

  def test_a_component_built_straight_on_the_library_is_held_to_it_too
    found = check(<<~RUBY)
      class CardComponent < ViewComponent::Base
        def initialize(person:)
          @person = person
        end
      end
    RUBY

    assert_equal 1, found.length,
                 "a leaf inheriting the library base directly is the same gap, not a new one"
  end

  def test_a_component_below_a_base_is_not_asked_again
    assert_empty check("class CardComponent < ApplicationViewComponent\nend\n"),
                 "the sweep is inherited, so a component below the base declares nothing"
  end

  def test_a_leading_colon3_names_the_same_base
    assert_equal 1, check("class ApplicationComponent < ::ViewComponent::Base\nend\n").length,
                 "`::ViewComponent::Base` and `ViewComponent::Base` name one thing"
  end

  def test_a_class_inheriting_something_else_is_not_this_cop_s_business
    assert_empty check("class Money < Shape\nend\n"),
                 "it reads the superclass as written; anything else is another cop's business"
  end

  def test_the_base_and_the_sweep_are_configurable
    source = "class ApplicationComponent < Phlex::HTML\nend\n"

    assert_empty offences(source, cop_class: COP, path: PATH)
    assert_equal 1, offences(source, cop_class: COP, path: PATH,
                                     cop_config: { "Bases" => ["Phlex::HTML"] }).length
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: PATH)
  end
end
