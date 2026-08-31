# frozen_string_literal: true

require "test_helper"

# Watched to fail: deleting any one of the three refusals in Settings#initialize reddens
# its own test here and nothing else. A guard nobody has seen fail reads as coverage.
class SettingsTest < Minitest::Test
  KINDS = {
    "command" => ["app/commands/**/*.rb"],
    "query" => ["app/queries/**/*.rb"],
  }.freeze

  MATRIX = { "command" => ["query"], "query" => [] }.freeze

  def test_it_parses_a_sound_configuration
    settings = Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX)

    assert_equal ["query"], settings.reachable_from("command")
    assert_empty settings.reachable_from("query")
  end

  def test_an_unknown_kind_answers_nothing_rather_than_raising
    settings = Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX)

    assert_empty settings.reachable_from("workflow"),
      "It bounces rather than defaulting. A kind nobody declared answers nothing, and answering nothing is how a cop reports zero offences while protecting nothing."
  end

  def test_a_row_naming_itself_is_refused
    error = assert_raises(Shipshape::Error) do
      Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX.merge("query" => ["query"]))
    end

    assert_includes error.message, "lists query, which is a sister of it"
  end

  def test_a_row_naming_an_undeclared_kind_is_refused
    error = assert_raises(Shipshape::Error) do
      Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX.merge("command" => ["quer"]))
    end

    assert_includes error.message, "which no Kinds entry declares"
  end

  def test_a_glob_with_a_wildcard_in_the_middle_is_accepted
    kinds = KINDS.merge("query" => ["packs/*/queries/**/*.rb"])

    assert_equal ["query"], Shipshape::Settings.new(kinds: kinds, matrix: MATRIX).reachable_from("command"),
      "A mid-path wildcard is legitimate — it is how a Packwerk layout is expressed — and Kinds expands it into one autoload root per pack."
  end

  # The arguments are asserted where they arrive, and the assertion raises rather than
  # coercing: a Hash of the wrong shape is the caller's defect.
  def test_a_wrongly_shaped_configuration_raises_at_the_seam
    assert_raises(ArgumentError) { Shipshape::Settings.new(kinds: "app/commands", matrix: MATRIX) }
    assert_raises(ArgumentError) { Shipshape::Settings.new(kinds: KINDS, matrix: { "command" => "query" }) }
    assert_raises(ArgumentError) { Shipshape::Settings.new(kinds: { "command" => "glob" }, matrix: MATRIX) }
  end
end
