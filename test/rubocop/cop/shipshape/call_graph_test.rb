# frozen_string_literal: true

require "test_helper"

# Watched to fail, as `a-guard-states-its-limit` requires: replacing the matrix check in
# CallGraph#on_send with an unconditional return reddens four of these — the record, the
# controller, the leading-`::` and the safe-navigation cases. Restoring it returns them to
# green. A guard nobody has seen fail reads as coverage.
class CallGraphTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "request_handling" => ["app/controllers/**/*.rb"],
      "operation" => ["app/operations/**/*.rb"],
      "value" => ["app/values/**/*.rb"],
      "record" => ["app/records/**/*.rb"],
    },
    "Matrix" => {
      "request_handling" => ["operation"],
      "operation" => %w[operation value record],
      "value" => ["value"],
      "record" => [],
    },
  }.freeze

  TREE = [
    "app/operations/create_person.rb",
    "app/operations/geography/list_places.rb",
    "app/values/place.rb",
    "app/records/person_record.rb",
  ].freeze

  def test_a_declared_pair_is_allowed
    assert_empty check(<<~RUBY, "app/controllers/people_controller.rb")
      class PeopleController
        def create
          CreatePerson.call(name: "x")
        end
      end
    RUBY
  end

  def test_a_pair_absent_from_the_matrix_is_an_offence
    found = check(<<~RUBY, "app/controllers/people_controller.rb")
      class PeopleController
        def index
          PersonRecord.all
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A request_handling may not call a record"
    assert_includes found.first.message, "Declared: operation."
    assert_equal "PersonRecord", found.first.location.source
  end

  def test_a_kind_that_may_call_nothing_says_so
    found = check(<<~RUBY, "app/records/person_record.rb")
      class PersonRecord
        def rank
          CreatePerson.call(name: name)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "may not call anything"
  end

  def test_a_namespaced_constant_resolves_through_its_path
    assert_empty check(<<~RUBY, "app/operations/create_person.rb")
      class CreatePerson
        def call
          Geography::ListPlaces.call
        end
      end
    RUBY
  end

  def test_a_leading_colon_colon_names_the_same_thing
    found = check(<<~RUBY, "app/records/person_record.rb")
      class PersonRecord
        def places
          ::Geography::ListPlaces.call
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  def test_an_unresolvable_constant_is_skipped_not_failed
    assert_empty check(<<~RUBY, "app/records/person_record.rb")
      class PersonRecord
        def formatted
          Kernel.format("%s", name)
        end
      end
    RUBY
  end

  def test_a_file_outside_every_declared_kind_is_skipped
    assert_empty check(<<~RUBY, "lib/tasks/import.rb")
      CreatePerson.call(name: "x")
    RUBY
  end

  def test_a_call_through_a_local_is_invisible_which_is_the_stated_limit
    assert_empty check(<<~RUBY, "app/records/person_record.rb")
      class PersonRecord
        def rank
          operation = CreatePerson
          operation.call(name: name)
        end
      end
    RUBY
  end

  def test_a_safe_navigation_call_is_caught_too
    found = check(<<~RUBY, "app/records/person_record.rb")
      class PersonRecord
        def rank
          CreatePerson&.call(name: name)
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  private

  def check(source, path)
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE)
  end
end
