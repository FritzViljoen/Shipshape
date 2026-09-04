# frozen_string_literal: true

require "test_helper"

# The legacy pair share one glob — `*_legacy.rb` says "this is a door", and the base class
# says which of the two it is. So these cases exercise superclass resolution, not path
# resolution, and the tree here holds real class bodies rather than empty files.
class LegacyDoorTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "deed" => ["app/deeds/**/*.rb"],
      "question" => ["app/questions/**/*.rb"],
      "legacy_question" => ["app/legacy/**/*_legacy.rb"],
      "legacy_deed" => ["app/legacy/**/*_legacy.rb"],
      "shape" => ["app/shapes/**/*.rb"],
    },
    "BaseClasses" => {
      "deed" => ["Deed"],
      "question" => ["Question"],
      "legacy_question" => ["LegacyQuestion"],
      "legacy_deed" => ["LegacyDeed"],
      "shape" => ["Shape"],
    },
    "Sisters" => [%w[deed legacy_deed], %w[question legacy_question]],
    "Matrix" => {
      "deed" => %w[question legacy_question shape],
      "question" => ["shape"],
      "legacy_deed" => %w[question legacy_question shape],
      "legacy_question" => ["shape"],
      "shape" => [],
    },
  }.freeze

  TREE = {
    "app/deeds/create_person.rb" => "class CreatePerson < Deed\nend\n",
    "app/questions/list_people.rb" => "class ListPeople < Question\nend\n",
    "app/legacy/find_booking_legacy.rb" => "class FindBookingLegacy < LegacyQuestion\nend\n",
    "app/legacy/cancel_booking_legacy.rb" => "class CancelBookingLegacy < LegacyDeed\nend\n",
    "app/shapes/place.rb" => "class Place < Shape\nend\n",
  }.freeze

  # A deed may read through the reading door, exactly as it may read through a question.
  def test_a_deed_may_reach_the_reading_door
    assert_empty check(<<~RUBY, "app/deeds/create_person.rb")
      class CreatePerson < Deed
        def call
          FindBookingLegacy.call
        end
      end
    RUBY
  end

  def test_a_deed_may_not_reach_the_writing_door
    found = check(<<~RUBY, "app/deeds/create_person.rb")
      class CreatePerson < Deed
        def call
          CancelBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A deed may not call a legacy_deed"
    assert_includes found.first.message, "They are sisters",
      "A legacy deed IS a deed — it only wraps something old. So a deed calling one is a write sequencing a write, and the reason is the transaction: a deed is exactly one, and it has just nested or silently widened it without anybody deciding to."
  end

  # A workflow is several transactions, which is exactly why it is the one that may
  # sequence them.
  def test_a_workflow_sequences_both_doors
    workflow = {
      "Kinds" => CONFIG["Kinds"].merge("workflow" => ["app/workflows/**/*.rb"]),
      "BaseClasses" => CONFIG["BaseClasses"].merge("workflow" => ["Workflow"]),
      "Sisters" => CONFIG["Sisters"],
      "Matrix" => CONFIG["Matrix"].merge("workflow" => %w[deed question legacy_deed legacy_question shape]),
    }
    tree = TREE.merge("app/workflows/settle_month.rb" => "class SettleMonth < Workflow\nend\n")

    assert_empty offences(<<~RUBY, cop_class: COP, cop_config: workflow, path: "app/workflows/settle_month.rb", files: tree)
      class SettleMonth < Workflow
        def call
          CancelBookingLegacy.call
          CreatePerson.call(name: "x")
        end
      end
    RUBY
  end

  def test_a_question_may_not_reach_the_reading_door_either_it_is_a_sister
    found = check(<<~RUBY, "app/questions/list_people.rb")
      class ListPeople < Question
        def call
          FindBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A question may not call a legacy_question"
    assert_includes found.first.message, "They are sisters",
      "The whole reason there are two doors: the return shape survives the crossing."
  end

  def test_a_question_may_not_reach_the_writing_door
    found = check(<<~RUBY, "app/questions/list_people.rb")
      class ListPeople < Question
        def call
          CancelBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A question may not call a legacy_deed"
  end

  def test_the_two_doors_are_told_apart_by_their_base_class
    found = check(<<~RUBY, "app/legacy/find_booking_legacy.rb")
      class FindBookingLegacy < LegacyQuestion
        def call
          CancelBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A legacy_question may not call a legacy_deed",
      "Two files under one glob, told apart only by what they inherit."
  end

  def test_one_door_may_not_call_its_own_kind
    found = check(<<~RUBY, "app/legacy/find_booking_legacy.rb")
      class FindBookingLegacy < LegacyQuestion
        def call
          OtherLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "They are sisters."
  end

  # A door's whole job is to speak to the old world, and the old world is unclassified —
  # so it is skipped, and the door may say anything it likes to it.
  def test_a_door_may_call_the_old_world
    assert_empty check(<<~RUBY, "app/legacy/find_booking_legacy.rb")
      class FindBookingLegacy < LegacyQuestion
        def call
          ::BookingService.new.find(1)
        end
      end
    RUBY
  end

  private

  def check(source, path)
    tree = TREE.merge("app/legacy/other_legacy.rb" => "class OtherLegacy < LegacyQuestion\nend\n")

    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: tree)
  end
end
