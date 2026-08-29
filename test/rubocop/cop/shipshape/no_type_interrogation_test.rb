# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Emptying `ASKS` reddens the predicate tests.
# - Making `on_case` return early reddens the case test.
# - Making `asserting?` answer false reddens the guard-implementation test, which is the one
#   place the ask is the assertion rather than a dispatch.
class NoTypeInterrogationTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::NoTypeInterrogation

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "record" => ["app/records/**/*_record.rb"],
      },
      "Matrix" => { "command" => ["record"], "record" => [] },
    },
  }.freeze

  COMMAND = "app/commands/price_party.rb"

  def test_a_predicate_is_a_dispatch
    found = check(<<~RUBY)
      class PriceParty
        def call
          @party.is_a?(Group) ? group_rate : single_rate
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`is_a?` asks what kind of thing this is"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(<<~RUBY).first.message
      class PriceParty
        def call
          return 0 if @party.kind_of?(Group)
        end
      end
    RUBY

    assert_includes message, "WHY: A variant that has to be asked about is not substitutable"
    assert_includes message, "INSTEAD:"
    assert_includes message, "party.rate"
  end

  def test_every_ask_in_the_family_is_caught
    found = check(<<~RUBY)
      class PriceParty
        def call
          a = @party.is_a?(Group)
          b = @party.kind_of?(Group)
          c = @party.instance_of?(Group)
          d = @party.respond_to?(:head_count)
          [a, b, c, d]
        end
      end
    RUBY

    assert_equal 4, found.length
  end

  def test_a_case_over_classes_is_a_dispatch
    found = check(<<~RUBY)
      class PriceParty
        def call
          case @party
          when Group then group_rate
          when Solo then single_rate
          end
        end
      end
    RUBY

    assert_equal 2, found.length
    assert_includes found.first.message, "chain of `is_a?` with better syntax"
  end

  # A case on a value, not on a type.
  def test_a_case_over_values_is_not_a_dispatch_on_type
    assert_empty check(<<~RUBY)
      class PriceParty
        def call
          case @state
          when "held" then 0
          when "sold" then 1
          end
        end
      end
    RUBY
  end

  # An assertion has one outcome. That is the whole difference.
  def test_asserting_a_type_is_allowed
    assert_empty check(<<~RUBY)
      class PriceParty
        def initialize(party:)
          @party = typed(party, Party)
        end
      end
    RUBY
  end

  def test_the_guard_helper_is_exempt_by_name
    assert_empty check(<<~RUBY)
      class PriceParty
        def typed(value, type, allow_nil: false)
          return value if value.is_a?(type)

          raise TypeError
        end
      end
    RUBY
  end

  # The trees the cop does not cover are where a real edge lives.
  def test_a_record_is_outside_the_cops_scope
    assert_empty offences(<<~RUBY, cop_class: COP, path: "app/records/party_record.rb", other_cops: LAYOUT)
      class PartyRecord < ApplicationRecord
        def self.wrap(raw)
          raw.is_a?(Hash) ? new(raw) : raw
        end
      end
    RUBY
  end

  # Four spellings of one ask. The law names the act, not the syntax.
  def test_comparing_the_class_is_the_same_ask
    found = check(<<~RUBY)
      class PriceParty
        def call
          a = @party.class == Group
          b = @party.class.name == "Group"
          c = Group === @party
          [a, b, c]
        end
      end
    RUBY

    assert_equal 3, found.length
  end

  # A value constant in a `when` is a comparison, not a dispatch on type. Failing these was
  # the cop firing on every state machine in the codebase.
  def test_a_case_over_value_constants_is_not_a_dispatch
    assert_empty check(<<~RUBY)
      class PriceParty
        def call
          case @state
          when Booking::HELD then 0
          when Booking::SOLD then 1
          end
        end
      end
    RUBY
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: COMMAND, other_cops: LAYOUT)
  end
end
