# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Making `decided?` answer true reddens every offence test.
# - Emptying `ASSOCIATIONS` reddens them too.
# - Making `decided?` answer false reddens the three tests that assert an option is accepted,
#   which are the ones that matter: the law is that somebody chose, not that they chose
#   `:destroy`.
class AssociationsSurviveErasureTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::AssociationsSurviveErasure

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "record" => ["app/models/**/*.rb"],
        "command" => ["app/commands/**/*.rb"],
      },
      "Matrix" => { "record" => [], "command" => [] },
    },
  }.freeze

  RECORD = "app/models/user.rb"

  def test_an_association_with_no_dependent_is_refused
    found = check("has_many :comments")

    assert_equal 1, found.length
    assert_includes found.first.message, "does not say what happens to comments"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("has_many :comments").first.message

    assert_includes message, "WHY: For an erasure request that is the whole failure"
    assert_includes message, "it is often the wrong answer"
    assert_includes message, "INSTEAD:"
    assert_includes message, "dependent: :nullify"
  end

  def test_any_decision_is_accepted
    assert_empty check("has_many :comments, dependent: :destroy")
    assert_empty check("has_many :comments, dependent: :nullify")
    assert_empty check("has_many :comments, dependent: :restrict_with_error"),
      "**The law is that somebody chose**, not that they chose to delete. Every option passes."
  end

  def test_it_covers_the_associations_that_own_children
    assert_equal 1, check("has_one :profile").length
    assert_equal 1, check("has_and_belongs_to_many :groups").length
  end

  def test_belongs_to_is_not_this_cops_business
    assert_empty check("belongs_to :account"),
      "`belongs_to` points the other way: the row it names is not this row's to delete."
  end

  def test_an_association_outside_a_record_is_left_alone
    assert_empty check("has_many :comments", "app/commands/settle.rb")
  end

  def test_other_options_are_not_a_decision_about_children
    assert_equal 1, check("has_many :comments, inverse_of: :user").length
  end

  private

  def check(body, path = RECORD)
    declaration = path == RECORD ? "class User < ApplicationRecord" : "class Settle < Command"

    offences("#{declaration}\n  #{body}\nend\n", cop_class: COP, path: path, other_cops: LAYOUT)
  end
end
