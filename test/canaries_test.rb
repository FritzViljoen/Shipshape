# frozen_string_literal: true

require "test_helper"
require "open3"
require "shipshape/canaries"

# **A guard that does not run reports the same thing as a guard that finds nothing.**
# Watched to fail: broke NoSilentCoercion's TEMPLATE with a bare `%w[a b]`; only test_no_cops_message_raises_while_rendering reddened, naming the cop, where the older silent-canary test could not have said why.
class CanariesTest < Minitest::Test
  ROOT = File.expand_path("canaries", __dir__)

  def test_every_cop_catches_the_violation_planted_for_it
    assert result.ok?,
           "These cops did not catch a violation written specifically for them, so they are " \
           "protecting nothing: #{result.silent.join(', ')}. Usually a kind's paths in " \
           "Shipshape/CallGraph no longer match where the code lives."
  end

  def test_no_cops_message_raises_while_rendering
    assert_empty result.crashed,
                 "rubocop caught these cops raising while computing their own offense " \
                 "message and printed a crash to stderr instead of reporting the offense, " \
                 "so above they read as merely \"silent\" with no hint why: " \
                 "#{result.crashed.join(', ')}. Usually a `format` template holds a literal " \
                 "`%` that is not a valid conversion, or the hash passed to it is missing a " \
                 "key the template names. Render the template by hand against the planted " \
                 "canary and fix it."
  end

  def test_the_crash_line_pattern_matches_rubocops_actual_crash_sentence
    err = crash_a_cop

    assert_match Shipshape::Canaries::CRASH_LINE, err,
                 "Shipshape::Canaries::CRASH_LINE parses rubocop's own crash sentence and " \
                 "found none in rubocop's real output: #{err.strip.inspect}. Rubocop reworded " \
                 "it; update the pattern in lib/shipshape/canaries.rb to match, or every " \
                 "crashed cop will silently read as merely \"silent\" above."
    assert_equal CRASHING_COP_NAME, err[Shipshape::Canaries::CRASH_LINE, 1],
                 "CRASH_LINE matched something, but not the crashed cop's own name, in: " \
                 "#{err.strip.inspect}"
  end

  def test_every_fired_cops_message_is_rendered
    blank = result.fired.reject do |cop|
      result.messages.fetch(cop, []).all? { |message| message.is_a?(String) && !message.strip.empty? }
    end

    assert_empty blank,
                 "These cops reported an offense with no message text, so nothing a reader " \
                 "sees explains what is wrong or what to do instead: #{blank.join(', ')}. " \
                 "An unrendered message is an unproven message; pass a real `message:` to " \
                 "`add_offense`, or define `MSG`."
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

  # A single-pass camelCase split collapsed a doubled capital and a leading article into the
  # word before it — the same bug fixed in canon_test.rb and removal_test.rb, dormant here only
  # because no registered cop's name currently exercises it.
  def test_slug_splits_a_doubled_capital_and_a_leading_article
    assert_equal "absence_is_absence_never_a_value",
                 canaries.send(:slug, "Shipshape/AbsenceIsAbsenceNeverAValue"),
                 "A single-pass conversion collapses a doubled capital or a leading article, " \
                 "so a cop whose name carries one is silently orphaned from its own test " \
                 "file — this has already bitten canon_test.rb and removal_test.rb."
  end

  private

  CRASHING_COP_NAME = "CanarySignal/Crashes"

  CRASHING_COP = <<~RUBY
    module RuboCop
      module Cop
        module CanarySignal
          class Crashes < Base
            def on_int(node)
              add_offense(node, message: format("%w[a b]"))
            end
          end
        end
      end
    end
  RUBY

  # Runs the real rubocop binary against a cop built to raise while rendering its offense
  # message, and hands back its stderr — proving the pattern against what rubocop itself
  # prints today, not against a copy of it.
  def crash_a_cop
    Dir.mktmpdir("crash-signal") do |dir|
      File.write(File.join(dir, "cop.rb"), CRASHING_COP)
      File.write(File.join(dir, "target.rb"), "X = 1\n")
      File.write(File.join(dir, ".rubocop.yml"), <<~YAML)
        require:
          - ./cop.rb
        AllCops:
          NewCops: disable
        #{CRASHING_COP_NAME}:
          Enabled: true
      YAML

      command = [RbConfig.ruby, Gem.bin_path("rubocop", "rubocop"), "--only", CRASHING_COP_NAME,
                 "--format", "json", "--no-color", "."]
      _out, err, = Open3.capture3(*command, chdir: dir)

      return err
    end
  end

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
