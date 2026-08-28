# frozen_string_literal: true

require "test_helper"

# Watched to fail, as `a-guard-states-its-limit` requires. Three checks, proven separately:
#
# - Making `check_methods` return early reddens the second-method and wrong-name tests.
# - Making `check_reader` return early reddens the public-attr_reader test.
# - Making `reason_to_refuse` answer nil reddens all four parameter tests.
#
# Restoring each returns them to green. A guard nobody has seen fail reads as coverage.
class OneOperationOneClassTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OneOperationOneClass

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "query" => ["app/queries/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
        "record" => ["app/records/**/*_record.rb"],
      },
      "Matrix" => { "command" => %w[query record], "query" => ["record"], "record" => [], "shape" => [] },
    },
  }.freeze

  CONFIG = { "OperationKinds" => %w[command query], "PublicMethod" => "call" }.freeze

  TREE = ["app/commands/create_person.rb", "app/queries/list_people.rb", "app/shapes/place.rb"].freeze

  def test_one_public_call_with_keywords_is_the_shape
    assert_empty check(<<~RUBY)
      class CreatePerson
        def initialize(name:, joined_on:)
          @name = name
          @joined_on = joined_on
        end

        def call
          PersonRecord.create!(name: @name)
        end

        private

        attr_reader :name, :joined_on
      end
    RUBY
  end

  def test_a_second_public_method_is_a_second_operation
    found = check(<<~RUBY)
      class CreatePerson
        def call; end

        def preview; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`preview` is a second"
  end

  def test_the_public_method_is_named_call
    found = check(<<~RUBY)
      class CreatePerson
        def perform; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "is `call`, not `perform`"
  end

  def test_private_methods_are_not_counted
    assert_empty check(<<~RUBY)
      class CreatePerson
        def call
          build
        end

        private

        def build; end

        def persist; end
      end
    RUBY
  end

  def test_an_inline_private_def_is_not_counted
    assert_empty check(<<~RUBY)
      class CreatePerson
        def call; end

        private def build; end
      end
    RUBY
  end

  def test_a_public_reader_is_a_public_method_in_all_but_name
    found = check(<<~RUBY)
      class CreatePerson
        attr_reader :name

        def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`attr_reader` here is a public method"
  end

  def test_a_positional_parameter_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(name)
          @name = name
        end

        def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`name` is positional"
  end

  def test_an_optional_positional_parameter_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(name = "x"); end

        def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "is positional"
  end

  # A keyword-less initializer silently accepts a caller's keywords as one positional
  # Hash and the call succeeds — which is why this is its own offence and not tolerated.
  def test_a_collected_keyword_parameter_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(**options); end

        def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "a collected keyword"
  end

  def test_a_collected_positional_parameter_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(*args); end

        def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "a collected positional"
  end

  def test_keywords_with_defaults_are_fine
    assert_empty check(<<~RUBY)
      class CreatePerson
        def initialize(name:, joined_on: nil); end

        def call; end
      end
    RUBY
  end

  # The cop only speaks to operations. A shape or a record is governed by its own laws.
  def test_a_file_of_another_kind_is_left_alone
    assert_empty check(<<~RUBY, "app/shapes/place.rb")
      class Place
        attr_reader :code

        def initialize(code)
          @code = code
        end

        def parent_code; end
      end
    RUBY
  end

  def test_a_file_outside_every_declared_kind_is_left_alone
    assert_empty check(<<~RUBY, "lib/tasks/import.rb")
      class Import
        def initialize(path); end

        def call; end

        def preview; end
      end
    RUBY
  end

  # The stated limit, asserted rather than claimed: length is a separate concern.
  def test_a_long_call_passes_which_is_the_stated_limit
    body = Array.new(50) { |index| "    step_#{index}" }.join("\n")

    assert_empty check(<<~RUBY)
      class CreatePerson
        def call
      #{body}
        end

        private

      #{Array.new(50) { |index| "  def step_#{index}; end" }.join("\n")}
      end
    RUBY
  end

  # The law is about what a CALLER may hand an operation, and a caller can hand it only
  # `initialize` and `call`. A private helper's arguments are internal.
  #
  # This cop checked every `def` at first, and on a well-built application it reported
  # sixteen offences that were all private helpers. A guard that fires on correct code is
  # not strict, it is wrong, and it is how a cop gets disabled wholesale.
  def test_a_private_helper_may_take_positional_arguments
    assert_empty check(<<~RUBY)
      class CreatePerson
        def initialize(name:)
          @name = name
        end

        def call
          apply(build(@name), 1)
        end

        private

        def build(name)
          name
        end

        def apply(value, count)
          [value, count]
        end
      end
    RUBY
  end

  def test_the_entry_points_are_still_checked
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(name)
          @name = name
        end

        def call(extra)
          extra
        end
      end
    RUBY

    assert_equal 2, found.length
  end

  private

  def check(source, path = "app/commands/create_person.rb")
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE, other_cops: LAYOUT)
  end
end
