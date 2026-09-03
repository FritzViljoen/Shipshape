# frozen_string_literal: true

require "test_helper"
require "shipshape/measures/naming"

class Shipshape::Measures::NamingTest < Minitest::Test
  Naming = Shipshape::Measures::Naming

  def test_a_consonant_y_still_becomes_ies
    assert_equal "galleries", Naming.plural("gallery")
    assert_equal "categories", Naming.plural("category")
  end

  def test_a_vowel_y_takes_a_plain_s
    assert_equal "gateways", Naming.plural("gateway")
    assert_equal "keys", Naming.plural("key")
    assert_equal "surveys", Naming.plural("survey")
    assert_equal "journeys", Naming.plural("journey")
    assert_equal "displays", Naming.plural("display")
    assert_equal "holidays", Naming.plural("holiday")
    assert_equal "alloys", Naming.plural("alloy")
    assert_equal "closed_days", Naming.plural("closed_day")
  end

  def test_an_already_plural_word_is_left_alone
    assert_equal "billing_settings", Naming.plural("billing_settings")
  end

  def test_the_sibilant_clusters_still_take_es
    assert_equal "boxes", Naming.plural("box")
    assert_equal "churches", Naming.plural("church")
    assert_equal "classes", Naming.plural("class")
    assert_equal "dishes", Naming.plural("dish")
  end

  def test_a_genuine_irregular_still_guesses_wrong
    assert_equal "persons", Naming.plural("person")
  end
end
