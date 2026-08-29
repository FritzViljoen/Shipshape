# frozen_string_literal: true

require "test_helper"

# The legacy pair share one glob — `*_legacy.rb` says "this is a door", and the base class
# says which of the two it is. So these cases exercise superclass resolution, not path
# resolution, and the tree here holds real class bodies rather than empty files.
#
# Watched to fail: making Kinds#by_base_class answer nil reddens every case below that
# depends on telling the two doors apart. Restoring it returns them to green.
class LegacyDoorTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "command" => ["app/commands/**/*.rb"],
      "query" => ["app/queries/**/*.rb"],
      "legacy_query" => ["app/legacy/**/*_legacy.rb"],
      "legacy_command" => ["app/legacy/**/*_legacy.rb"],
      "shape" => ["app/shapes/**/*.rb"],
    },
    "BaseClasses" => {
      "command" => ["Command"],
      "query" => ["Query"],
      "legacy_query" => ["LegacyQuery"],
      "legacy_command" => ["LegacyCommand"],
      "shape" => ["Shape"],
    },
    "Sisters" => [%w[command legacy_command], %w[query legacy_query]],
    "Matrix" => {
      "command" => %w[query legacy_query shape],
      "query" => ["shape"],
      "legacy_command" => %w[query legacy_query shape],
      "legacy_query" => ["shape"],
      "shape" => [],
    },
  }.freeze

  TREE = {
    "app/commands/create_person.rb" => "class CreatePerson < Command\nend\n",
    "app/queries/list_people.rb" => "class ListPeople < Query\nend\n",
    "app/legacy/find_booking_legacy.rb" => "class FindBookingLegacy < LegacyQuery\nend\n",
    "app/legacy/cancel_booking_legacy.rb" => "class CancelBookingLegacy < LegacyCommand\nend\n",
    "app/shapes/place.rb" => "class Place < Shape\nend\n",
  }.freeze

  # A command may read through the reading door, exactly as it may read through a query.
  def test_a_command_may_reach_the_reading_door
    assert_empty check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson < Command
        def call
          FindBookingLegacy.call
        end
      end
    RUBY
  end

  # A legacy command IS a command — it only wraps something old. So a command calling one
  # is a write sequencing a write, and the reason is the transaction: a command is exactly
  # one, and it has just nested or silently widened it without anybody deciding to.
  def test_a_command_may_not_reach_the_writing_door
    found = check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson < Command
        def call
          CancelBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A command may not call a legacy_command"
    assert_includes found.first.message, "They are sisters"
  end

  # A workflow is several transactions, which is exactly why it is the one that may
  # sequence them.
  def test_a_workflow_sequences_both_doors
    workflow = {
      "Kinds" => CONFIG["Kinds"].merge("workflow" => ["app/workflows/**/*.rb"]),
      "BaseClasses" => CONFIG["BaseClasses"].merge("workflow" => ["Workflow"]),
      "Sisters" => CONFIG["Sisters"],
      "Matrix" => CONFIG["Matrix"].merge("workflow" => %w[command query legacy_command legacy_query shape]),
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

  # The whole reason there are two doors: the return shape survives the crossing.
  def test_a_query_may_not_reach_the_reading_door_either_it_is_a_sister
    found = check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople < Query
        def call
          FindBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call a legacy_query"
    assert_includes found.first.message, "They are sisters"
  end

  def test_a_query_may_not_reach_the_writing_door
    found = check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople < Query
        def call
          CancelBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call a legacy_command"
  end

  # Two files under one glob, told apart only by what they inherit.
  def test_the_two_doors_are_told_apart_by_their_base_class
    found = check(<<~RUBY, "app/legacy/find_booking_legacy.rb")
      class FindBookingLegacy < LegacyQuery
        def call
          CancelBookingLegacy.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A legacy_query may not call a legacy_command"
  end

  def test_one_door_may_not_call_its_own_kind
    found = check(<<~RUBY, "app/legacy/find_booking_legacy.rb")
      class FindBookingLegacy < LegacyQuery
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
      class FindBookingLegacy < LegacyQuery
        def call
          ::BookingService.new.find(1)
        end
      end
    RUBY
  end

  private

  def check(source, path)
    tree = TREE.merge("app/legacy/other_legacy.rb" => "class OtherLegacy < LegacyQuery\nend\n")

    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: tree)
  end
end
