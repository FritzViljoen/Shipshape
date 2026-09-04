# frozen_string_literal: true

require "test_helper"
require "shipshape/config_at"
require "fileutils"
require "tmpdir"

# Watched to fail: reverting `#call` to a bare `store.for_dir(dir)` reddens
# `test_a_cop_this_version_lacks_is_skipped_and_named` with a raw `RuboCop::ValidationError`.
class ConfigAtTest < Minitest::Test
  def test_a_cop_this_version_lacks_is_skipped_and_named
    in_dir("Shipshape/DoesNotExistAnymore:\n  Enabled: true\n") do |dir|
      result = Shipshape::ConfigAt.call(dir, config: File.join(dir, ".rubocop.yml"), tolerate_unknown_cops: true)

      assert_equal ["Shipshape/DoesNotExistAnymore"], result.skipped_cops
      refute_nil result.config
    end
  end

  def test_without_tolerance_the_same_config_still_raises
    in_dir("Shipshape/DoesNotExistAnymore:\n  Enabled: true\n") do |dir|
      assert_raises(RuboCop::ValidationError) do
        Shipshape::ConfigAt.call(dir, config: File.join(dir, ".rubocop.yml"), tolerate_unknown_cops: false)
      end
    end
  end

  def test_a_known_cop_is_never_reported_skipped
    in_dir("Layout/LineLength:\n  Enabled: false\n") do |dir|
      result = Shipshape::ConfigAt.call(dir, config: File.join(dir, ".rubocop.yml"), tolerate_unknown_cops: true)

      assert_empty result.skipped_cops
    end
  end

  # Tolerance is scoped to one raise site - malformed YAML must still fail loudly.
  def test_malformed_yaml_still_raises_even_when_tolerant
    in_dir("Shipshape/CallGraph: [not valid yaml\n") do |dir|
      assert_raises(Psych::SyntaxError) do
        Shipshape::ConfigAt.call(dir, config: File.join(dir, ".rubocop.yml"), tolerate_unknown_cops: true)
      end
    end
  end

  # The global switch this reads is always restored after a tolerant call.
  def test_the_global_switch_is_restored_after_a_tolerant_call
    in_dir("Shipshape/DoesNotExistAnymore:\n  Enabled: true\n") do |dir|
      Shipshape::ConfigAt.call(dir, config: File.join(dir, ".rubocop.yml"), tolerate_unknown_cops: true)

      refute RuboCop::ConfigLoader.ignore_unrecognized_cops
    end
  end

  private

  def in_dir(cop_config)
    Dir.mktmpdir("shipshape-config-at") do |dir|
      File.write(File.join(dir, ".rubocop.yml"), <<~YAML)
        AllCops:
          NewCops: disable

        #{cop_config}
      YAML

      yield(dir)
    end
  end
end
