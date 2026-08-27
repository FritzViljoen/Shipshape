# frozen_string_literal: true

require "test_helper"

# Watched to fail, as `a-guard-states-its-limit` requires. Two checks, proven separately:
#
# - Neutering the matrix check in CallGraph#allowed? reddens four — the record, the
#   controller, the leading-`::` and the safe-navigation cases.
# - Making the same-kind check permit instead of refuse reddens four others — query,
#   command, workflow and entity calling their own kind.
#
# Restoring each returns them to green. A guard nobody has seen fail reads as coverage.
class CallGraphTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "request_handling" => ["app/controllers/**/*_controller.rb"],
      "workflow" => ["app/workflows/**/*.rb"],
      "query" => ["app/queries/**/*.rb"],
      "command" => ["app/commands/**/*.rb"],
      "entity" => ["app/entities/**/*.rb"],
      "record" => ["app/records/**/*_record.rb"],
    },
    "Matrix" => {
      "request_handling" => %w[workflow command query],
      "workflow" => %w[command query],
      "command" => %w[query entity record],
      "query" => %w[entity record],
      "entity" => [],
      "record" => [],
    },
  }.freeze

  TREE = [
    "app/workflows/settle_month.rb",
    "app/workflows/close_books.rb",
    "app/commands/create_person.rb",
    "app/commands/geography/create_place.rb",
    "app/queries/list_people.rb",
    "app/queries/geography/list_places.rb",
    "app/queries/stripe/fetch_rates.rb",
    "app/commands/stripe/send_invoice.rb",
    "app/entities/place.rb",
    "app/entities/money.rb",
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

  # One rule, applied to every kind: no kind calls its own kind. The per-kind reasons
  # below are consequences of it, not separate rules.
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
    assert_includes found.first.message, "no kind calls a sister"
  end

  def test_a_command_may_not_call_a_command
    found = check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson
        def call
          Geography::CreatePlace.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A command may not call a command"
  end

  def test_a_command_may_read_through_a_query
    assert_empty check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson
        def call
          ListPeople.call
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

  def test_a_workflow_may_not_call_a_workflow
    found = check(<<~RUBY, "app/workflows/settle_month.rb")
      class SettleMonth
        def call
          CloseBooks.call
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

  # Whose store it is changes nothing. A read of somebody else's is a query, so a query
  # reaching one is the same sister call as a query reaching a local query.
  def test_a_remote_read_is_a_query
    found = check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople
        def call
          Stripe::FetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call a query"
  end

  def test_a_remote_write_is_a_command
    found = check(<<~RUBY, "app/commands/create_person.rb")
      class CreatePerson
        def call
          Stripe::SendInvoice.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A command may not call a command"
  end

  def test_a_workflow_sequences_a_local_write_and_a_remote_one
    assert_empty check(<<~RUBY, "app/workflows/settle_month.rb")
      class SettleMonth
        def call
          CreatePerson.call(name: "x")
          Stripe::SendInvoice.call
        end
      end
    RUBY
  end

  def test_an_entity_may_not_call_an_entity
    found = check(<<~RUBY, "app/entities/place.rb")
      class Place
        def total
          Money.new(cents: 1)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "An entity may not call an entity"
  end

  # The rule lives in the cop, not in the matrix — so no configuration can permit a
  # sister call, and a row that tries is a contradiction rather than a permission.
  def test_a_matrix_row_naming_itself_is_refused
    permissive = CONFIG.merge("Matrix" => CONFIG["Matrix"].merge("query" => %w[query entity record]))

    error = assert_raises(Shipshape::Error) do
      offences(<<~RUBY, cop_class: COP, cop_config: permissive, path: "app/queries/list_people.rb", files: TREE)
        class ListPeople
          def call
            PersonRecord.all
          end
        end
      RUBY
    end

    assert_includes error.message, "lists query, which is a sister of it"
  end

  # A Packwerk layout has no top-level app/. The glob's trailing wildcards are dropped and
  # what remains is expanded on disk, giving one autoload root per pack.
  def test_a_packwerk_layout_resolves_per_pack
    packs = {
      "Kinds" => {
        "command" => ["packs/*/commands/**/*.rb"],
        "query" => ["packs/*/queries/**/*.rb"],
        "record" => ["packs/*/records/**/*_record.rb"],
      },
      "Matrix" => { "command" => %w[query record], "query" => ["record"], "record" => [] },
    }
    tree = %w[
      packs/billing/commands/charge.rb
      packs/catalogue/queries/list_items.rb
      packs/catalogue/records/item_record.rb
    ]

    found = offences(<<~RUBY, cop_class: COP, cop_config: packs, path: "packs/catalogue/queries/list_items.rb", files: tree)
      class ListItems
        def call
          Charge.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call a command"
    assert_includes found.first.message, "Declared: record."
  end

  # Each pack is its own autoload root, so two packs may hold the same constant name and
  # each resolves within its own tree.
  def test_a_record_in_another_pack_is_still_a_record
    packs = {
      "Kinds" => {
        "query" => ["packs/*/queries/**/*.rb"],
        "record" => ["packs/*/records/**/*_record.rb"],
      },
      "Matrix" => { "query" => ["record"], "record" => [] },
    }
    tree = %w[packs/catalogue/queries/list_items.rb packs/billing/records/invoice_record.rb]

    assert_empty offences(<<~RUBY, cop_class: COP, cop_config: packs, path: "packs/catalogue/queries/list_items.rb", files: tree)
      class ListItems
        def call
          InvoiceRecord.all
        end
      end
    RUBY
  end

  # The suffix is load-bearing, and this is the hole it cuts: a file in the records tree
  # that is not named `*_record.rb` has no kind, so it is skipped rather than failed. The
  # law says so, and `shipshape check` reports the count of unclassified files, because a
  # tree that silently drops out of coverage is the failure this canon exists to prevent.
  def test_a_file_missing_the_suffix_its_kind_requires_has_no_kind
    assert_empty check(<<~RUBY, "app/records/person.rb")
      class Person
        def rank
          CreatePerson.call(name: name)
        end
      end
    RUBY
  end

  def test_the_same_file_with_the_suffix_is_classified
    found = check(<<~RUBY, "app/records/person_record.rb")
      class PersonRecord
        def rank
          CreatePerson.call(name: name)
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  # A class naming itself is not a call between two of a kind. `Result.success(...)`
  # inside `Result` is one entity, and the call graph has nothing to say about it.
  def test_a_class_naming_itself_is_not_a_sister_call
    assert_empty check(<<~RUBY, "app/entities/place.rb")
      class Place
        def self.root
          Place.new(code: "ROOT")
        end
      end
    RUBY
  end

  def test_a_workflow_naming_itself_is_not_a_sister_call_either
    assert_empty check(<<~RUBY, "app/workflows/settle_month.rb")
      class SettleMonth
        RETRY = SettleMonth
      end
    RUBY
  end

  private

  def check(source, path)
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE)
  end
end
