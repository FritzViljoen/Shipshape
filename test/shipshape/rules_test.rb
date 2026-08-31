# frozen_string_literal: true

require "test_helper"
require "shipshape/rules"
require "shipshape/install"

# Watched to fail: hard-code the kinds table and the layout test reddens; drop the registry read
# in `cops` and the guards test reddens; ignore `root` and both authorisation tests redden.
# Everything here is derived, so these assert it tracks its inputs rather than fixed prose.
class RulesTest < Minitest::Test
  def test_it_names_the_kinds_the_configuration_declares
    rules = generate

    assert_includes rules, "| `command` |"
    assert_includes rules, "app/commands/**/*.rb"
  end

  def test_it_names_every_loaded_cop_with_its_own_description
    rules = generate

    RuboCop::Cop::Registry.global.cops.map(&:cop_name).grep(%r{\AShipshape/}).each do |cop|
      assert_includes rules, "**`#{cop}`**", "#{cop} is loaded but the rules file omits it"
    end
  end

  def test_it_says_what_each_kind_may_call
    assert_includes generate, "## What may call what"
  end

  def test_it_is_silent_about_authorisation_when_none_is_installed
    Dir.mktmpdir("rules-off") do |root|
      Shipshape::Install.new(root: root, auth: false).call

      refute_includes generate(root: root), "## Authorisation",
        "The section is written only where the base classes actually carry a permission check."
    end
  end

  def test_it_explains_authorisation_when_it_is_installed
    Dir.mktmpdir("rules-on") do |root|
      Shipshape::Install.new(root: root, auth: true).call
      rules = generate(root: root)

      assert_includes rules, "## Authorisation"
      assert_includes rules, "anonymous_call"
    end
  end

  def test_it_says_it_is_generated
    assert_includes generate, Shipshape::Rules::HEADER
  end

  # The one file an agent is handed carries it, or it is a fact nobody opened.
  def test_the_kinds_table_says_which_are_destinations
    rules = generate

    assert_includes rules, "| `legacy_command` |"
    assert_includes rules, "on its way out — never move code here"
    assert_includes rules, "a waypoint, not a destination"
  end

  private

  def generate(root: Dir.pwd)
    Shipshape::Rules.new(config: RuboCop::ConfigStore.new.for_pwd, root: root).call
  end
end
