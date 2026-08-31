# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `PRESENCE` reddens every offence test, and dropping `empty?` from it
# reddens the empty test — the one that matters, since `blank?` consults `empty?`.
class PresenceIsNotRedefinedTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::PresenceIsNotRedefined

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "shape" => ["app/shapes/**/*.rb"], "record" => ["app/models/**/*.rb"] },
      "Matrix" => { "shape" => [], "record" => [] },
    },
  }.freeze

  SHAPE = "app/shapes/basket.rb"

  def test_a_shape_answering_present_is_an_offence
    found = check("class Basket < Shape\n  def present?\n    false\n  end\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`present?` decides what `present?` answers"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("class Basket < Shape\n  def present?\n    false\n  end\nend\n").first.message

    assert_includes message, "WHY: Request handling may test `present?` and nothing else"
    assert_includes message, "INSTEAD:"
    assert_includes message, "computes nothing"
  end

  # `blank?` consults `empty?`, so that name decides the answer without ever saying `present?`.
  def test_blank_and_empty_decide_it_too
    %w[blank? empty?].each do |name|
      found = check("class Basket < Shape\n  def #{name}\n    true\n  end\nend\n")

      assert_equal 1, found.length, name
    end
  end

  def test_a_class_method_is_the_same_answer
    assert_equal 1, check("class Basket < Shape\n  def self.empty?\n    true\n  end\nend\n").length
  end

  def test_a_shape_that_says_nothing_about_presence_is_the_shape
    assert_empty check(<<~RUBY)
      class Basket < Shape
        def initialize(lines:)
          @lines = lines
        end

        attr_reader :lines
      end
    RUBY
  end

  # A record is a table, and `empty?` on one is Active Record's, not a shape's answer.
  def test_a_record_is_not_this_cop_s_business
    assert_empty offences("class BasketRecord < ApplicationRecord\n  def empty?\n    true\n  end\nend\n",
                          cop_class: COP, path: "app/models/basket_record.rb", other_cops: LAYOUT)
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: SHAPE, other_cops: LAYOUT)
  end
end
