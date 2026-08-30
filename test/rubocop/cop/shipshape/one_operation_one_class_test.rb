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

  def test_a_private_call_with_keywords_is_the_shape
    assert_empty check(<<~RUBY)
      class CreatePerson
        def initialize(name:, joined_on:)
          @name = name
          @joined_on = joined_on
        end

        private

        private

        def call
          PersonRecord.create!(name: @name)
        end

        attr_reader :name, :joined_on
      end
    RUBY
  end

  # **The whole public surface is the inherited class method.** Left public, `call` is a
  # second entrance: a caller can write `CreatePerson.new(...).call` and go around the door,
  # taking the permission check, the transaction and the return-type assertion with it.
  def test_a_public_entry_point_is_a_second_entrance
    found = check(<<~RUBY)
      class CreatePerson
        def call
          PersonRecord.create!(name: @name)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`call` is public, and an operation exposes nothing"
    assert_includes found.first.message, "forwarding method"
  end

  def test_a_second_public_method_is_a_second_operation
    found = check(<<~RUBY)
      class CreatePerson
        def preview; end

        private

        private def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`preview` is public"
  end

  def test_a_public_method_of_any_name_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def perform; end

        private

        private def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`perform` is public"
  end

  def test_private_methods_are_not_counted
    assert_empty check(<<~RUBY)
      class CreatePerson
        private

        def call
          build
        end

        def build; end

        def persist; end
      end
    RUBY
  end

  def test_an_inline_private_def_is_not_counted
    assert_empty check(<<~RUBY)
      class CreatePerson
        private def call; end

        private def build; end
      end
    RUBY
  end

  def test_a_public_reader_is_a_public_method_in_all_but_name
    found = check(<<~RUBY)
      class CreatePerson
        attr_reader :name

        private

        private def call; end
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

        private def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`name` is positional"
  end

  def test_an_optional_positional_parameter_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(name = "x"); end

        private def call; end
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

        private def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "a collected keyword"
  end

  def test_a_collected_positional_parameter_is_refused
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(*args); end

        private def call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "a collected positional"
  end

  def test_keywords_with_defaults_are_fine
    assert_empty check(<<~RUBY)
      class CreatePerson
        def initialize(name:, joined_on: nil); end

        private def call; end
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

        private def call; end

        def preview; end
      end
    RUBY
  end

  # The stated limit, asserted rather than claimed: length is a separate concern.
  def test_a_long_call_passes_which_is_the_stated_limit
    body = Array.new(50) { |index| "    step_#{index}" }.join("\n")

    assert_empty check(<<~RUBY)
      class CreatePerson
        private

        def call
      #{body}
        end

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

        private

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

  # `initialize` and the entry point are what a caller hands arguments to, so both are
  # checked — and the entry point being private does not exempt it.
  def test_the_entry_points_are_still_checked
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(name)
          @name = name
        end

        private

        def call(extra)
          extra
        end
      end
    RUBY

    assert_equal 2, found.length
  end

  # The base class runs whichever of the two this class implements, so a class implementing
  # neither has nothing to run — and one inheriting an entry point inherits that operation's
  # answers, including whether it needs an actor at all.
  def test_an_operation_must_define_its_own_entry_point
    found = check(<<~RUBY)
      class CreatePerson
        def initialize(name:)
          @name = typed(name, String)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "defines neither `call` nor `anonymous_call`"
  end

  # A shape's whole job is to expose the fields it was handed, so judging a nested part by
  # the operation's rules flags `attr_reader` on the one class that must have it. Found by
  # using this on a real refactor.
  def test_a_nested_shape_may_expose_its_fields
    assert_empty check(<<~RUBY)
      class ReplyDraft
        private

        def call
          [Draft.new(subject: "x")]
        end

        public

        class Draft
          def initialize(subject:)
            @subject = typed(subject, String)
          end

          attr_reader :subject
        end
      end
    RUBY
  end

  # `Invoice::Line` — a part reached only through the class that declared it. The canon
  # blesses this shape, so requiring an entry point of it fires on correct code.
  def test_a_nested_part_needs_no_entry_point
    assert_empty check(<<~RUBY)
      class CreatePerson
        class Outcome
          def initialize(total:)
            @total = typed(total, Integer)
          end
        end

        private

        def call
          success(:done)
        end
      end
    RUBY
  end

  # The permission model requires this name: an operation running before anyone is
  # identified says so by implementing it instead of `call`.
  def test_anonymous_call_is_an_entry_point
    assert_empty check(<<~RUBY)
      class CreatePerson
        private

        def anonymous_call
          success(:in)
        end
      end
    RUBY
  end

  # **Both, and both private, is a fail-open.** `anonymous?` answers true, so the base class
  # dispatches to `anonymous_call` and the operation runs unauthenticated — while the file
  # appears to define an authorised `call`. Visibility cannot catch this: the correct shape
  # is private too.
  def test_defining_both_entry_points_is_refused_even_when_both_are_private
    found = check(<<~RUBY)
      class CreatePerson
        private

        def call; end

        def anonymous_call; end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`anonymous_call` is a second entry point"
    assert_includes found.first.message, "runs unauthenticated"
  end

  # The advice matters as much as the finding: a public helper is almost never a second
  # operation, it is a method that forgot to go under `private`.
  def test_a_public_helper_is_told_to_go_private
    message = check(<<~RUBY).first.message
      class CreatePerson
        def total
          1
        end

        private

        def call
          total
        end
      end
    RUBY

    assert_includes message, "`total` is public"
    assert_includes message, "it is a helper, and it goes under `private`"
    assert_includes message, "occasionally: it is a second operation"
  end

  # A private helper is the shape, and there may be as many as the operation needs.
  def test_private_helpers_are_the_shape
    assert_empty check(<<~RUBY)
      class CreatePerson
        private

        def call
          total + tax
        end

        def total
          1
        end

        def tax
          2
        end
      end
    RUBY
  end

  # **A shape is the presenter level, and it may expose whatever it likes.** Its whole job is
  # to be read: readers, formatters, derived values that only rearrange fields it was handed.
  # `OperationKinds` leaves it out, and this pins that so nobody narrows it later.
  def test_a_shape_may_have_public_helpers
    assert_empty offences(<<~RUBY, cop_class: COP, cop_config: CONFIG, path: "app/shapes/invoice.rb",
      class Invoice
        def initialize(number:)
          @number = typed(number, String)
        end

        attr_reader :number

        def formatted
          "INV-\#{@number}"
        end

        def short
          @number.last(4)
        end
      end
    RUBY
                          files: TREE, other_cops: LAYOUT)
  end

  private

  def check(source, path = "app/commands/create_person.rb")
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: TREE, other_cops: LAYOUT)
  end
end
