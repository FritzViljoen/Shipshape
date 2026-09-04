# frozen_string_literal: true

require "test_helper"
require "shipshape/guards"
require "open3"
require "fileutils"

# A real directory and a real `rubocop --show-cops` subprocess: the mechanism is the shape
# RuboCop prints, and stubbing it would test the filter and leave that shape unchecked.
class GuardsTest < Minitest::Test
  RUBOCOP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
      BaseClasses:
        command: [Command]

    Shipshape/OneOperationOneClass:
      Enabled: false

    Layout/LineLength:
      Enabled: false
  YAML

  NOTHING_OFF_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
      BaseClasses:
        command: [Command]
  YAML

  PENDING_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
      BaseClasses:
        command: [Command]

    Shipshape/OneOperationOneClass:
      Enabled: pending
  YAML

  PENDING_ENABLED_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: enable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
      BaseClasses:
        command: [Command]

    Shipshape/OneOperationOneClass:
      Enabled: pending
  YAML

  UNLOADABLE_YML = "Shipshape/CallGraph: [not valid yaml\n"

  # `--config` resolves via `ConfigStore#options_config=`, which never validates this.
  OUT_OF_RANGE_RUBY_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false
      TargetRubyVersion: 3.5

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
      BaseClasses:
        command: [Command]

    Shipshape/OneOperationOneClass:
      Enabled: pending
  YAML

  def test_a_disabled_shipshape_cop_is_named
    in_repo(RUBOCOP_YML) do |root|
      off = call(root)

      assert_includes off, "Shipshape/OneOperationOneClass"
    end
  end

  # `pending` does not run until a repo opts in with `NewCops: enable`, so it is as off as
  # `false` and must be disclosed the same way.
  def test_a_pending_shipshape_cop_is_named
    in_repo(PENDING_YML) do |root|
      assert_includes call(root), "Shipshape/OneOperationOneClass"
    end
  end

  # The other half: once the repo opts in, `pending` runs and must not be named as off.
  def test_a_pending_shipshape_cop_is_not_named_once_new_cops_are_enabled
    in_repo(PENDING_ENABLED_YML) do |root|
      refute_includes call(root), "Shipshape/OneOperationOneClass"
    end
  end

  # Regression: pending resolution used to validate the config unconditionally, and crashed
  # on a `TargetRubyVersion` `--show-cops --config` itself never validates.
  def test_a_pending_cop_resolves_with_an_out_of_range_target_ruby_version
    in_repo(OUT_OF_RANGE_RUBY_YML) do |root|
      assert_includes call(root), "Shipshape/OneOperationOneClass"
    end
  end

  # Compares Guards' subprocess answer to `RuboCop::ConfigStore` asked directly, in-process.
  def test_pending_resolution_agrees_with_configstore_directly
    in_repo(PENDING_YML) do |root|
      config_path = File.join(root, ".rubocop.yml")
      store = RuboCop::ConfigStore.new
      store.options_config = config_path
      enabled = store.for_dir(root).enabled_new_cop?("Shipshape/OneOperationOneClass")

      off = call(root)

      assert_equal !enabled, off.include?("Shipshape/OneOperationOneClass")
    end
  end

  def test_an_enabled_shipshape_cop_is_not_named
    in_repo(RUBOCOP_YML) do |root|
      off = call(root)

      refute_includes off, "Shipshape/CallGraph"
    end
  end

  # This gem's own cops are the only thing being disclosed; the repository's other cops are
  # none of our business.
  def test_a_disabled_cop_outside_the_department_is_not_named
    in_repo(RUBOCOP_YML) do |root|
      off = call(root)

      refute_includes off, "Layout/LineLength"
    end
  end

  def test_nothing_disabled_is_an_empty_list
    in_repo(NOTHING_OFF_YML) do |root|
      assert_empty call(root)
    end
  end

  def test_a_config_rubocop_cannot_load_is_refused
    in_repo(UNLOADABLE_YML) do |root|
      error = assert_raises(Shipshape::Error) { call(root) }

      assert_includes error.message, "produced no report"
    end
  end

  RETIRED_COP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/RetiredCopName:
      Enabled: true
  YAML

  # Shares `Coupling`'s exposure: a config naming a cop this version's registry does not hold
  # crashes `--show-cops` the same way it crashes the in-process read - `check` never actually
  # asks Guards about the base tree, but the class itself must survive being asked to.
  def test_a_config_naming_an_unknown_cop_is_refused_without_tolerance
    in_repo(RETIRED_COP_YML) do |root|
      error = assert_raises(Shipshape::Error) { call(root) }

      assert_includes error.message, "produced no report"
    end
  end

  def test_a_config_naming_an_unknown_cop_is_tolerated_and_named
    in_repo(RETIRED_COP_YML) do |root|
      guards = Shipshape::Guards.new(directory: root, config: File.join(root, ".rubocop.yml"),
                                      tolerate_unknown_cops: true)

      assert_empty guards.call
      assert_includes guards.skipped_cops, "Shipshape/RetiredCopName"
    end
  end

  # `--show-cops` always prints valid YAML, so this reaches the guard the other way.
  def test_output_that_fails_to_parse_is_refused
    guards = Shipshape::Guards.new(directory: Dir.mktmpdir("shipshape-guards"))

    guards.stub(:yaml, "# rubocop --show-cops\nfoo: [1, 2\n") do
      error = assert_raises(Shipshape::Error) { guards.call }

      assert_includes error.message, "produced no report"
    end
  end

  private

  def call(root)
    Shipshape::Guards.new(directory: root, config: File.join(root, ".rubocop.yml")).call
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end

  # `rubocop --show-cops` runs as a subprocess, so it needs the gem on its load path the way a
  # real consumer would have it from the Gemfile — RUBYOPT says that to the child without
  # teaching Guards a test-only argument.
  def in_repo(config)
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip

    Dir.mktmpdir("shipshape-guards") do |root|
      File.write(File.join(root, ".rubocop.yml"), config)
      yield(root)
    end
  ensure
    ENV["RUBYOPT"] = was
  end
end
