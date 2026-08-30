# frozen_string_literal: true

require "test_helper"
require "shipshape/canaries"

# **A guard that does not run reports the same thing as a guard that finds nothing.**
#
# This is not hypothetical. shipshape's cops were run over a 647-file tree and reported
# zero, which read as "clean" and meant "no glob matched, so nothing was inspected". Neither
# the unit tests nor `rake test:removal` could have caught it: both build a config in
# memory, and what broke was the real configuration's globs.
#
# `test/canaries/` holds one deliberate violation per cop, with its own `.rubocop.yml`
# beside it so the globs resolve there. This runs the real binary over them.
#
# Watched to fail: point a kind's globs at a directory that does not exist and the cops
# scoped to that kind go silent — six of them, on the run that proved this.
class CanariesTest < Minitest::Test
  ROOT = File.expand_path("canaries", __dir__)

  def test_every_cop_catches_the_violation_planted_for_it
    assert result.ok?,
           "These cops did not catch a violation written specifically for them, so they are " \
           "protecting nothing: #{result.silent.join(', ')}. Usually a kind's paths in " \
           "Shipshape/CallGraph no longer match where the code lives."
  end

  # **Every registered cop, not every enabled one.** Filtering on the configuration meant a
  # cop shipped `Enabled: false` needed no canary — while `CanonTest` still demanded a law and
  # a test for it, so it read as fully covered while nothing could prove it fires. The planted
  # tree turns every cop on for its own run, so the canary answers either way.
  def test_every_cop_has_a_canary
    assert_empty result.unplanted,
                 "Add a canary to Shipshape::Canaries::PLANTED for each of these, then " \
                 "re-plant with `shipshape canaries --plant`."
  end

  # The planted tree has to stay in step with the planting code — otherwise this passes
  # against files nobody regenerated.
  def test_the_checked_in_canaries_match_what_the_planter_writes
    Shipshape::Canaries::PLANTED.each_key do |cop|
      next unless result.fired.include?(cop) || result.silent.include?(cop)

      assert_path_exists File.join(ROOT, planted.fetch(cop)),
                         "#{cop}'s canary is missing; re-plant with `shipshape canaries --plant`"
    end
  end

  # **The checked-in configuration is generated, so it can drift from the generator.** The
  # tree beside it is checked for existence above; this checks the file that decides whether
  # any of it is inspected at all. It went stale once already, in the change that added the
  # force-enable block — a canary tree nobody regenerates reports the same thing as a cop that
  # works.
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
