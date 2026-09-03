# frozen_string_literal: true

require "test_helper"

# Watched to fail: emptying `CONSTANTS` reddens every offence test; making `one_of?` answer true
# reddens the io_command test, which is the one that matters: a cop that fires on the kind whose
# job is the outside enforces the opposite of the law. **The call matrix cannot hold this.** It
# refuses `command -> io_command`, which works only for IO an application already filed as a kind.
class IoIsItsOwnKindTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::IoIsItsOwnKind

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "query" => ["app/queries/**/*.rb"],
        "io_command" => ["app/io_commands/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => {
        "command" => ["Command"], "query" => ["Query"],
        "io_command" => ["IoCommand"], "shape" => ["Shape"]
      },
      "Matrix" => { "command" => [], "query" => [], "io_command" => [], "shape" => [] },
    },
  }.freeze

  COMMAND = "app/commands/settle_invoice.rb"

  def test_io_from_a_command_is_refused
    found = check("Net::HTTP.get(URI(\"http://example.com\"))")

    assert_equal 1, found.length
    assert_includes found.first.message, "`Net::HTTP.get` talks to the outside, and a command does not"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("Faraday.get(\"http://example.com\")").first.message

    assert_includes message, "WHY: A command is exactly one transaction"
    assert_includes message, "The call matrix cannot refuse this"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class ChargeCard < IoCommand"
  end

  def test_io_from_a_query_is_refused_and_named_as_a_query
    found = check("RestClient.get(\"http://example.com\")", "app/queries/list_people.rb",
                  "class ListPeople < Query")

    assert_equal 1, found.length,
      "The worse case, because nothing about a read looks dangerous."
    assert_includes found.first.message, "and a query does not"
  end

  # The kind whose whole job is the outside.
  def test_an_io_command_may_talk_to_the_outside
    assert_empty check("Net::HTTP.get(URI(\"http://example.com\"))",
                       "app/io_commands/charge_card.rb", "class ChargeCard < IoCommand")
  end

  def test_a_leading_colon_colon_names_the_same_client
    assert_equal 1, check("::Faraday.get(\"http://example.com\")").length
  end

  def test_something_that_is_not_a_client_is_left_alone
    assert_empty check("Money.from_cents(1)")
  end

  def test_a_vendor_the_list_does_not_name_is_the_stated_blind_spot
    assert_empty check("Stripe::Charge.create(amount: 1)"),
      "The stated limit, pinned so the silence is deliberate rather than discovered."
  end

  # `File.join` is a string operation; `File.read` is not. Separating them needs a
  # per-constant method list that would drift, so the filesystem is left out by decision.
  def test_the_filesystem_is_absent_from_the_defaults_by_decision
    assert_empty check("File.read(\"/etc/hosts\")")
  end

  def test_an_application_may_add_its_own_vendors
    found = offences(source("Stripe::Charge.create(amount: 1)", "class SettleInvoice < Command"),
                     cop_class: COP, cop_config: { "Constants" => ["Stripe::Charge"] },
                     path: COMMAND, other_cops: LAYOUT)

    assert_equal 1, found.length
  end

  private

  def source(body, declaration)
    "#{declaration}\n  def call\n    #{body}\n  end\nend\n"
  end

  def check(body, path = COMMAND, declaration = "class SettleInvoice < Command")
    offences(source(body, declaration), cop_class: COP, path: path, other_cops: LAYOUT)
  end
end
