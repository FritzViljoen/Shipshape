# frozen_string_literal: true

require "test_helper"
require "shipshape/canaries"

# **A guard that does not run reports the same thing as a guard that finds nothing.**
class CanariesTest < Minitest::Test
  ROOT = File.expand_path("canaries", __dir__)

  def test_every_cop_catches_the_violation_planted_for_it
    assert result.ok?,
           "These cops did not catch a violation written specifically for them, so they are " \
           "protecting nothing: #{result.silent.join(', ')}. Usually a kind's paths in " \
           "Shipshape/CallGraph no longer match where the code lives."
  end

  def test_every_cop_has_a_canary
    assert_empty result.unplanted,
                 "Add a canary to Shipshape::Canaries::PLANTED for each of these, then " \
                 "re-plant with `shipshape canaries --plant`."
  end

  def test_the_checked_in_canaries_match_what_the_planter_writes
    Shipshape::Canaries::PLANTED.each_key do |cop|
      next unless result.fired.include?(cop) || result.silent.include?(cop)

      assert_path_exists File.join(ROOT, planted.fetch(cop)),
                         "#{cop}'s canary is missing; re-plant with `shipshape canaries --plant`"
    end
  end

  # The checked-in configuration is generated and can drift: it decides whether any of the tree
  # is inspected, and it went stale once, in the change that added the force-enable block.
  def test_the_checked_in_configuration_is_what_the_planter_writes
    assert_equal canaries.send(:configuration), File.read(File.join(ROOT, ".rubocop.yml")),
                 "Re-plant with `shipshape canaries --plant`, or regenerate this file."
  end

  private

  def canaries
    @canaries ||= Shipshape::Canaries.new(config: RuboCop::ConfigStore.new.for_pwd, root: ROOT)
  end

  def result
    @result ||= canaries.call
  end

  def planted
    canaries.send(:planted)
  end
end
