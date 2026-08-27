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
      "workflow" => ["app/workflows/**/*.rb"],
      "command" => ["app/commands/**/*.rb"],
      "query" => ["app/queries/**/*.rb"],
      "gateway" => ["app/gateways/**/*.rb"],
      "value" => ["app/values/**/*.rb"],
      "record" => ["app/records/**/*.rb"],
    },
    "Matrix" => {
      "request_handling" => %w[workflow command query],
      "workflow" => %w[command query gateway],
      "command" => %w[command query gateway value record],
      "query" => %w[value record],
      "gateway" => ["value"],
      "value" => ["value"],
      "record" => [],
    },
  }.freeze

  TREE = [
    "app/workflows/settle_month.rb",
    "app/commands/create_person.rb",
    "app/commands/geography/create_place.rb",
    "app/queries/list_people.rb",
    "app/queries/geography/list_places.rb",
    "app/gateways/payment_provider.rb",
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
    assert_includes found.first.message, "Declared: workflow, command, query."
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
    assert_empty check(<<~RUBY, "app/commands/create_person.rb")
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

  # A query is one read. A query calling a query is two reads wearing one name, and the
  # second is invisible to whoever asked — the shape an N+1 arrives in.
  def test_a_query_may_not_call_a_query
    found = check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople
        def call
          Geography::ListPlaces.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call a query"
    assert_includes found.first.message, "Declared: value, record."
  end

  def test_a_command_may_call_a_command
    assert_empty check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson
        def call
          Geography::CreatePlace.call
        end
      end
    RUBY
  end

  def test_a_workflow_sequences_commands_and_queries
    assert_empty check(<<~RUBY, "app/workflows/settle_month.rb")
      class SettleMonth
        def call
          ListPeople.call
          CreatePerson.call(name: "x")
        end
      end
    RUBY
  end

  # A workflow's whole content is its sequence. Nesting hides the sequence.
  def test_a_workflow_may_not_call_a_workflow
    found = check(<<~RUBY, "app/workflows/settle_month.rb")
      class SettleMonth
        def call
          SettleMonth.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A workflow may not call a workflow"
  end

  def test_a_query_may_read_a_record
    assert_empty check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople
        def call
          PersonRecord.all
        end
      end
    RUBY
  end

  def test_a_command_may_call_a_gateway
    assert_empty check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson
        def call
          PaymentProvider.call(amount: 1)
        end
      end
    RUBY
  end

  # The external call and the write that records its result are two visible steps. A
  # gateway that writes leaves a half-written row behind when the remote call fails.
  def test_a_gateway_may_not_reach_a_record
    found = check(<<~RUBY, "app/gateways/payment_provider.rb")
      class PaymentProvider
        def call
          PersonRecord.find(1)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A gateway may not call a record"
    assert_includes found.first.message, "Declared: value."
  end

  def test_a_gateway_may_not_read_through_a_query
    found = check(<<~RUBY, "app/gateways/payment_provider.rb")
      class PaymentProvider
        def call
          ListPeople.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A gateway may not call a query"
  end

  # An external call has a domain meaning, and the meaning lives in whatever wanted it.
  def test_request_handling_may_not_reach_a_gateway_directly
    found = check(<<~RUBY, "app/controllers/people_controller.rb")
      class PeopleController
        def create
          PaymentProvider.call(amount: 1)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A request_handling may not call a gateway"
  end

  private

  def check(source, path)
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE)
  end
end
