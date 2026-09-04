# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `FINDERS` reddens every offence test; making `params_read?` answer
# false reddens them too; making it answer true reddens the parsed-value test, which is the one
# that separates a raw parameter from a real value; making `param_reads` skip descendants reddens
# the nested-hash test.
class NoUnparsedLookupTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoUnparsedLookup

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "request_handling" => ["app/controllers/**/*_controller.rb"],
        "deed" => ["app/deeds/**/*.rb"],
      },
      "Matrix" => { "request_handling" => ["deed"], "deed" => [] },
    },
  }.freeze

  CONTROLLER = "app/controllers/people_controller.rb"

  def test_a_raw_parameter_reaching_a_finder_is_an_offence
    found = check(<<~RUBY)
      class PeopleController
        def show
          PersonRecord.find(params[:id])
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`params[:id]` reaches `find` unparsed"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class PeopleController
        def show
          PersonRecord.find(params[:id])
        end
      end
    RUBY

    assert_includes message, "WHY: This works, which is the trap"
    assert_includes message, "INSTEAD:"
    assert_includes message, "PersonRecord.find(integer_param!(:id))"
  end

  def test_a_parameter_in_a_hash_value_counts
    assert_equal 1, check(<<~RUBY).length
      class PeopleController
        def index
          BookingRecord.where(state: params[:state])
        end
      end
    RUBY
  end

  def test_a_parameter_nested_any_depth_down_counts
    assert_equal 1, check(<<~RUBY).length
      class PeopleController
        def index
          BookingRecord.where(person: { id: params.fetch(:person_id) })
        end
      end
    RUBY
  end

  def test_a_writer_counts_as_well_as_a_finder
    found = check(<<~RUBY)
      class PeopleController
        def create
          PersonRecord.create!(name: params[:name])
          PersonRecord.update(params[:id], name: "x")
        end
      end
    RUBY

    assert_equal 2, found.length
  end

  def test_a_parsed_value_is_the_shape
    assert_empty check(<<~RUBY)
      class PeopleController
        def show
          PersonRecord.find(integer_param!(:id))
          BookingRecord.where(state: enum_param!(:state, %w[held sold]))
        end
      end
    RUBY
  end

  def test_a_finder_on_something_that_is_not_a_parameter_is_fine
    assert_empty check(<<~RUBY)
      class PeopleController
        def show
          PersonRecord.find(@person.id)
        end
      end
    RUBY
  end

  def test_a_deed_is_outside_the_seam
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/deeds/find_person.rb", other_cops: LAYOUT)
      class FindPerson
        def call
          PersonRecord.find(params[:id])
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: CONTROLLER, other_cops: LAYOUT)
  end
end
