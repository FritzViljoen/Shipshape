# frozen_string_literal: true

require "test_helper"

# Watched to fail: neutering the matrix check in CallGraph#allowed? reddens four — the record, the
# controller, the leading-`::` and the safe-navigation cases; making the same-kind check permit
# instead of refuse reddens four others — query, command, workflow and shape calling their own
# kind. Restoring each returns them to green. A guard nobody has seen fail reads as coverage.
class CallGraphTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::CallGraph

  CONFIG = {
    "Kinds" => {
      "request_handling" => ["app/controllers/**/*_controller.rb"],
      "workflow" => ["app/workflows/**/*.rb"],
      "query" => ["app/queries/**/*.rb"],
      "command" => ["app/commands/**/*.rb"],
      "shape" => ["app/shapes/**/*.rb"],
      "record" => ["app/records/**/*_record.rb"],
    },
    "Matrix" => {
      "request_handling" => %w[workflow command query],
      "workflow" => %w[command query],
      "command" => %w[query shape record],
      "query" => %w[shape record],
      "shape" => [],
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
    "app/shapes/place.rb",
    "app/shapes/money.rb",
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
    assert_includes found.first.message, "They are sisters.",
      "One rule, applied to every kind: no kind calls its own kind. The per-kind reasons below are consequences of it, not separate rules."
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

  def test_a_remote_read_is_a_query
    found = check(<<~RUBY, "app/queries/list_people.rb")
      class ListPeople
        def call
          Stripe::FetchRates.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A query may not call a query",
      "Whose store it is changes nothing. A read of somebody else's is a query, so a query reaching one is the same sister call as a query reaching a local query."
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
    found = check(<<~RUBY, "app/shapes/place.rb")
      class Place
        def total
          Money.new(cents: 1)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A shape may not call a shape"
  end

  def test_a_matrix_row_naming_itself_is_refused
    permissive = CONFIG.merge("Matrix" => CONFIG["Matrix"].merge("query" => %w[query shape record]))

    error = assert_raises(Shipshape::Error) do
      offences(<<~RUBY, cop_class: COP, cop_config: permissive, path: "app/queries/list_people.rb", files: TREE)
        class ListPeople
          def call
            PersonRecord.all
          end
        end
      RUBY
    end

    assert_includes error.message, "lists query, which is a sister of it",
      "The rule lives in the cop, not in the matrix — so no configuration can permit a sister call, and a row that tries is a contradiction rather than a permission."
  end

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
    assert_includes found.first.message, "Declared: record.",
      "A Packwerk layout has no top-level app/. The glob's trailing wildcards are dropped and what remains is expanded on disk, giving one autoload root per pack."
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
  # inside `Result` is one shape, and the call graph has nothing to say about it.
  def test_a_class_naming_itself_is_not_a_sister_call
    assert_empty check(<<~RUBY, "app/shapes/place.rb")
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

  def test_a_glob_naming_one_file_classifies_that_constant
    mixed = {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "shape" => ["app/models/standing.rb"],
        "record" => ["app/models/contest.rb"],
      },
      "Matrix" => { "request_handling" => ["shape"], "shape" => [], "record" => [] },
    }
    tree = %w[app/models/contest.rb app/models/standing.rb]

    found = offences(<<~RUBY, cop_class: COP, cop_config: mixed, path: "app/controllers/contests_controller.rb", files: tree)
      class ContestsController
        def show
          Contest.find(1)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "A request_handling may not call a record",
      "A glob may name one file rather than a tree, which is how an application says two kinds share a directory before it has moved anything. Treating such a glob as a root resolved constants against its DIRECTORY and matched nothing — so a controller reaching straight into a record came back clean."
  end

  # And only that one. Resolving against the directory would classify every neighbour the
  # same way, which is the opposite failure and just as silent.
  def test_a_glob_naming_one_file_classifies_nothing_else_in_its_directory
    mixed = {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "record" => ["app/models/contest.rb"],
      },
      "Matrix" => { "request_handling" => [], "record" => [] },
    }
    tree = %w[app/models/contest.rb app/models/person.rb]

    assert_empty offences(<<~RUBY, cop_class: COP, cop_config: mixed, path: "app/controllers/contests_controller.rb", files: tree)
      class ContestsController
        def index
          Person.all
        end
      end
    RUBY
  end


  def test_a_declared_base_class_resolves_to_its_kind
    found = offences(<<~RUBY, cop_class: COP, cop_config: WITH_BASES, path: "app/shapes/place.rb", files: TREE)
      class Place < Shape
        def rows
          ActiveRecord::Base.connection.execute("select 1")
        end
      end
    RUBY

    assert_equal 1, found.length,
      "**A base class is its kind even though it lives in a gem.** Resolution goes through the filesystem, so `ActiveRecord::Base` resolved to nothing and was skipped — which meant the one constant that names persistence was the one nothing could see, and `ActiveRecord::Base.connection.execute` reached the database from a shape unopposed."
  end

  # **A parent is not a sister.** Once base classes resolve, a record naming the class it
  # inherits from counted as a record calling a record, and the offence said so — in words
  # that are not true of a superclass reference.
  def test_a_class_naming_its_own_base_class_is_not_a_sister_call
    assert_empty offences(<<~RUBY, cop_class: COP, cop_config: WITH_BASES, path: "app/records/person_record.rb", files: TREE)
      class PersonRecord < ApplicationRecord
        def self.recent
          ApplicationRecord.transaction { 1 }
        end
      end
    RUBY
  end

  def test_a_controller_naming_a_record_base_class_is_still_refused
    found = offences(<<~RUBY, cop_class: COP, cop_config: WITH_BASES, path: "app/controllers/things_controller.rb", files: TREE)
      class ThingsController < ApplicationController
        def create
          ActiveRecord::Base.transaction { 1 }
        end
      end
    RUBY

    assert_equal 1, found.length,
      "The exemption is the *own* superclass, not any base class."
  end

  # The coupling record travels as an offence, exactly as `BaseTestClassGrowth`'s span does -
  # read back by `Coupling` from RuboCop's own JSON, never from state held on this class.
  # `record_coupling` is a no-op unless the reader asks for it, so a plain `rubocop` run -
  # this test's default, `RECORD_COUPLING_ENV` unset - emits none of it.
  def test_a_coupling_record_is_not_emitted_unless_asked_for
    found = check(<<~RUBY, "app/controllers/people_controller.rb")
      class PeopleController
        def create
          CreatePerson.call(name: "x")
        end
      end
    RUBY

    assert_empty found, "neither the edge record nor the governed-caller marker fires unasked"
  end

  # `Coupling` tells a tree arriving under governance apart from a call arriving on it by
  # reading this back: every governed caller gets one, edges or not.
  def test_a_governed_caller_is_marked_even_with_no_outgoing_call
    found = with_coupling_recording do
      check(<<~RUBY, "app/records/person_record.rb")
        class PersonRecord
        end
      RUBY
    end

    assert_equal 1, found.length
    assert_equal COP::GOVERNED_MESSAGE, found.first.message
  end

  def test_an_ungoverned_file_is_not_marked
    found = with_coupling_recording do
      check(<<~RUBY, "app/lib/unclaimed.rb")
        class Unclaimed
        end
      RUBY
    end

    assert_empty found
  end

  # An allowed edge produces no violation at all, yet it is still coupling - the graph, not
  # the offences found on it.
  def test_an_allowed_edge_still_records_coupling
    found = with_coupling_recording do
      check(<<~RUBY, "app/controllers/people_controller.rb")
        class PeopleController
          def create
            CreatePerson.call(name: "x")
          end
        end
      RUBY
    end

    assert_equal 1, couplings(found).length
    assert_empty real_offences(found)
  end

  # A disallowed edge is both: a violation, and one more edge in the graph the violation was
  # found on. Neither reader steps on the other's count.
  def test_a_disallowed_edge_records_coupling_alongside_its_own_violation
    found = with_coupling_recording do
      check(<<~RUBY, "app/controllers/people_controller.rb")
        class PeopleController
          def index
            PersonRecord.all
          end
        end
      RUBY
    end

    assert_equal 1, couplings(found).length
    assert_equal 1, real_offences(found).length
  end

  # `Coupling` tells an edge whose endpoint changed which tree governs it apart from one that
  # did not by comparing files, so the record has to carry the callee's file, not just the fact
  # that some governed kind was called.
  def test_a_coupling_record_names_the_callee_s_file
    found = with_coupling_recording do
      check(<<~RUBY, "app/controllers/people_controller.rb")
        class PeopleController
          def create
            CreatePerson.call(name: "x")
          end
        end
      RUBY
    end

    assert_equal "#{COP::COUPLING_MESSAGE}app/commands/create_person.rb", couplings(found).first.message
  end

  # A name resolved only through `BaseClasses` has a kind and no file - governance can never
  # arrive at it or leave it, so there is nothing to name after the arrow.
  def test_a_coupling_record_to_a_base_class_names_no_file
    found = with_coupling_recording do
      offences(<<~RUBY, cop_class: COP, cop_config: WITH_BASES, path: "app/controllers/things_controller.rb", files: TREE)
        class ThingsController < ApplicationController
          def create
            ActiveRecord::Base.transaction { 1 }
          end
        end
      RUBY
    end

    assert_equal COP::COUPLING_MESSAGE, couplings(found).first.message
  end

  # `on_new_investigation` claims a range before `on_send` ever runs, and
  # `RuboCop::Cop::Base#add_offense` silently drops a second offence that lands on a range
  # already claimed - not a merge, nothing. A one-character `BaseClasses` name at the very top
  # of a file makes the real violation's receiver exactly the file's first byte, which is what
  # `marker_range` used to be. Watched to fail: reverting `marker_range` to `(0, 1)` reddens
  # this by dropping the real offence to zero.
  def test_a_marker_at_the_file_s_first_byte_would_swallow_a_real_violation_there
    found = with_coupling_recording do
      offences("C.call\n", cop_class: COP, cop_config: SHAPES_CALL_A_BASE_CLASS, path: "app/shapes/x.rb", files: TREE)
    end

    assert_equal 1, found.select { |offence| offence.message == COP::GOVERNED_MESSAGE }.length
    assert_equal 1, couplings(found).length
    assert_equal 1, real_offences(found).length, "the receiver's own range is the file's first byte - " \
                                                 "the marker must not claim it, or the real violation vanishes"
  end

  private

  SHAPES_CALL_A_BASE_CLASS = CONFIG.merge("BaseClasses" => { "command" => ["C"] }).freeze

  WITH_BASES = CONFIG.merge(
    "BaseClasses" => {
      "record" => %w[ApplicationRecord ActiveRecord::Base],
      "request_handling" => %w[ApplicationController],
      "shape" => %w[Shape],
    },
  ).freeze

  def check(source, path)
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE)
  end

  # `RECORD_COUPLING_ENV` is `Coupling`'s own signal to its subprocess - set and torn down
  # around one call here, never left on for a test that runs after this one.
  def with_coupling_recording
    was = ENV[COP::RECORD_COUPLING_ENV]
    ENV[COP::RECORD_COUPLING_ENV] = "1"
    yield
  ensure
    ENV[COP::RECORD_COUPLING_ENV] = was
  end

  def couplings(found)
    found.select { |offence| offence.message.start_with?(COP::COUPLING_MESSAGE) }
  end

  # Neither internal marker is a real offence: the edge record, and the once-per-file "this
  # caller is governed" marker `on_new_investigation` adds alongside it.
  def real_offences(found)
    found.reject { |offence| offence.message.start_with?(COP::COUPLING_MESSAGE) || offence.message == COP::GOVERNED_MESSAGE }
  end
end
