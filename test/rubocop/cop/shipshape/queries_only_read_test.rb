# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `WRITERS` reddens every offence test; making `record?` answer false
# reddens them too, and making it answer true reddens the not-a-record test; making `root_constant`
# look only one hop back reddens the chained-write test, which is the commonest shape of all. **The
# call graph cannot hold this.** A query reaching a record is exactly what a query is for, so the
class QueriesOnlyReadTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::QueriesOnlyRead

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "query" => ["app/queries/**/*.rb"],
        "command" => ["app/commands/**/*.rb"],
        "record" => ["app/records/**/*_record.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => { "query" => ["Query"], "command" => ["Command"], "shape" => ["Shape"] },
      "Matrix" => { "query" => %w[shape record], "command" => %w[shape record], "record" => [], "shape" => [] },
    },
  }.freeze

  TREE = {
    "app/records/person_record.rb" => "class PersonRecord < ApplicationRecord\nend\n",
    "app/shapes/place.rb" => "class Place < Shape\nend\n",
  }.freeze

  QUERY = "app/queries/list_people.rb"
  COMMAND = "app/commands/create_person.rb"

  def test_a_write_from_a_query_is_refused
    found = check("PersonRecord.create!(name: \"x\")")

    assert_equal 1, found.length
    assert_includes found.first.message, "`PersonRecord.create!` is a write, and a query is one read"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("PersonRecord.destroy_all").first.message

    assert_includes message, "WHY: A query opens no transaction"
    assert_includes message, "The call graph cannot catch it"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class CreatePerson < Command"
  end

  # The commonest write of all, and invisible to anything looking one hop back.
  def test_a_write_at_the_end_of_a_chain_is_refused
    assert_equal 1, check("PersonRecord.find(1).update!(name: \"x\")").length
  end

  def test_a_read_is_the_whole_point_of_a_query
    assert_empty check("PersonRecord.where(active: true).to_a")
    assert_empty check("PersonRecord.find(1)")
  end

  # A command may write. That is what it is for.
  def test_a_command_may_write
    assert_empty check("PersonRecord.create!(name: \"x\")", COMMAND)
  end

  # `save` on something that is not a record is somebody else's business.
  def test_a_writer_name_on_something_that_is_not_a_record_is_left_alone
    assert_empty check("Place.create!(code: \"ZA\")")
  end

  def test_a_write_through_a_local_is_the_stated_blind_spot
    assert_empty check("person = fetch\n    person.update!(name: \"x\")")
  end

  private

  def check(body, path = QUERY)
    klass = path == QUERY ? "class ListPeople < Query" : "class CreatePerson < Command"

    offences("#{klass}\n  def call\n    #{body}\n  end\nend\n",
             cop_class: COP, path: path, files: TREE, other_cops: LAYOUT)
  end
end
