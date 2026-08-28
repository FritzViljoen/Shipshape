# frozen_string_literal: true

require "shipshape/measures/classes_with_no_base_class"
require "shipshape/measures/classes_doing_several_things"
require "shipshape/measures/request_handling_that_decides"
require "shipshape/measures/request_handling_that_reaches_persistence"
require "shipshape/measures/persistence_with_behaviour"
require "shipshape/measures/lifecycle_callbacks"
require "shipshape/measures/input_parsed_in_the_action"
require "shipshape/measures/nullable_columns"
require "shipshape/measures/god_classes"
require "shipshape/measures/wide_tables"
require "shipshape/measures/asking_then_branching"
require "shipshape/measures/actions_calling_many_classes"

module Shipshape
  # What the report measures, in the order it reads best: the shape of the classes first,
  # then what request handling is doing, then what persistence is doing, then the schema.
  module Measures
    ALL = [
      ClassesWithNoBaseClass,
      ClassesDoingSeveralThings,
      GodClasses,
      RequestHandlingThatDecides,
      ActionsCallingManyClasses,
      AskingThenBranching,
      RequestHandlingThatReachesPersistence,
      PersistenceWithBehaviour,
      LifecycleCallbacks,
      InputParsedInTheAction,
      NullableColumns,
      WideTables,
    ].freeze
  end
end
