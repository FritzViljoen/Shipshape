# frozen_string_literal: true

require "test_helper"

# Watched to fail: deleting any one of the three refusals in Settings#initialize reddens
# its own test here and nothing else. A guard nobody has seen fail reads as coverage.
class SettingsTest < Minitest::Test
  KINDS = {
    "deed" => ["app/deeds/**/*.rb"],
    "question" => ["app/questions/**/*.rb"],
  }.freeze

  MATRIX = { "deed" => ["question"], "question" => [] }.freeze

  def test_it_parses_a_sound_configuration
    settings = Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX)

    assert_equal ["question"], settings.reachable_from("deed")
    assert_empty settings.reachable_from("question")
  end

  def test_an_unknown_kind_answers_nothing_rather_than_raising
    settings = Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX)

    assert_empty settings.reachable_from("workflow"),
      "It bounces rather than defaulting. A kind nobody declared answers nothing, and answering nothing is how a cop reports zero offences while protecting nothing."
  end

  def test_a_row_naming_itself_is_refused
    error = assert_raises(Shipshape::Error) do
      Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX.merge("question" => ["question"]))
    end

    assert_includes error.message, "lists question, which is a sister of it"
  end

  def test_a_row_naming_an_undeclared_kind_is_refused
    error = assert_raises(Shipshape::Error) do
      Shipshape::Settings.new(kinds: KINDS, matrix: MATRIX.merge("deed" => ["quer"]))
    end

    assert_includes error.message, "which no Kinds entry declares"
  end

  def test_a_glob_with_a_wildcard_in_the_middle_is_accepted
    kinds = KINDS.merge("question" => ["packs/*/questions/**/*.rb"])

    assert_equal ["question"], Shipshape::Settings.new(kinds: kinds, matrix: MATRIX).reachable_from("deed"),
      "A mid-path wildcard is legitimate — it is how a Packwerk layout is expressed — and Kinds expands it into one autoload root per pack."
  end

  # A sibling repository refactored INTO a shape that was itself deprecated.
  def test_a_kind_may_be_declared_on_its_way_out
    settings = Shipshape::Settings.new(kinds: { "deed" => ["app/deeds/**/*.rb"],
                                                "legacy_deed" => ["app/legacy/**/*.rb"] },
                                       matrix: { "deed" => [], "legacy_deed" => [] },
                                       retiring: ["legacy_deed"])

    assert settings.retiring?("legacy_deed")
    refute settings.retiring?("deed"), "everything else is a destination"
  end

  def test_retiring_a_kind_nobody_declared_is_refused_at_the_seam
    error = assert_raises(Shipshape::Error) do
      Shipshape::Settings.new(kinds: { "deed" => ["app/deeds/**/*.rb"] },
                              matrix: { "deed" => [] }, retiring: ["nonesuch"])
    end

    assert_includes error.message, "Retiring names nonesuch"
  end

  # The arguments are asserted where they arrive, and the assertion raises rather than
  # coercing: a Hash of the wrong shape is the caller's defect.
  def test_a_wrongly_shaped_configuration_raises_at_the_seam
    assert_raises(ArgumentError) { Shipshape::Settings.new(kinds: "app/deeds", matrix: MATRIX) }
    assert_raises(ArgumentError) { Shipshape::Settings.new(kinds: KINDS, matrix: { "deed" => "question" }) }
    assert_raises(ArgumentError) { Shipshape::Settings.new(kinds: { "deed" => "glob" }, matrix: MATRIX) }
  end
end
