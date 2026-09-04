# frozen_string_literal: true

require "test_helper"
require "shipshape/coupling"
require "shipshape/base_test_class_lines"

# The property this whole number exists for: moving a governed file — same class, same call
# sites, different path under the same recursive glob — must not move the count, and cutting
# the one call between two governed classes must. `test_a_move_leaves_it_flat` and
# `test_a_cut_call_falls` are that proof, side by side.
class CouplingTest < Minitest::Test
  RUBOCOP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
        query: ['app/queries/**/*.rb']
      BaseClasses:
        command: [Command]
        query: [Query]
      Sisters:
        - [command]
        - [query]
      Matrix:
        command: [query]
        query: []
  YAML

  DISABLED_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Enabled: false
  YAML

  COMMAND = "class CreatePerson < Command\n  def call\n    ListPeople.call\n  end\nend\n"
  QUERY = "class ListPeople < Query\n  def call\n    []\n  end\nend\n"

  def test_an_allowed_edge_still_counts
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", COMMAND)
      write(root, "app/queries/list_people.rb", QUERY)

      assert_equal 1, call(root), "coupling counts a legal edge - it is the graph, not the violations on it"
    end
  end

  # A sister call is always a violation (Matrix names no sister), and still one edge.
  def test_a_disallowed_edge_counts_the_same_as_an_allowed_one
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/queries/list_people.rb", "class ListPeople < Query\n  def call\n    Other.call\n  end\nend\n")
      write(root, "app/queries/other.rb", "class Other < Query\n  def call\n    []\n  end\nend\n")

      assert_equal 1, call(root)
    end
  end

  def test_a_call_to_an_ungoverned_class_does_not_count
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", "class CreatePerson < Command\n  def call\n    Time.zone.now\n  end\nend\n")

      assert_equal 0, call(root)
    end
  end

  def test_a_superclass_reference_does_not_count
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", "class CreatePerson < Command\n  def call\n    Command.transaction { }\n  end\nend\n")

      assert_equal 0, call(root)
    end
  end

  # The property the whole number exists to prove: a file moved under the same recursive glob,
  # calls untouched, must read exactly the same.
  def test_a_move_leaves_it_flat
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", COMMAND)
      write(root, "app/queries/list_people.rb", QUERY)

      before = call(root)

      moved_command = File.join(root, "app/commands/people/create_person.rb")
      FileUtils.mkdir_p(File.dirname(moved_command))
      FileUtils.mv(File.join(root, "app/commands/create_person.rb"), moved_command)

      moved_query = File.join(root, "app/queries/people/list_people.rb")
      FileUtils.mkdir_p(File.dirname(moved_query))
      FileUtils.mv(File.join(root, "app/queries/list_people.rb"), moved_query)

      assert_equal before, call(root), "both files moved, no call site touched - the count must not move"
    end
  end

  # Same starting tree as the move above; this time the call itself is cut. The two tests
  # together are the proof: moving is flat, cutting is not.
  def test_a_cut_call_falls
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", COMMAND)
      write(root, "app/queries/list_people.rb", QUERY)

      before = call(root)

      write(root, "app/commands/create_person.rb", "class CreatePerson < Command\n  def call\n  end\nend\n")

      after = call(root)

      assert_equal 1, before
      assert_equal 0, after
    end
  end

  def test_the_governed_set_names_every_caller_kind_file_regardless_of_edges
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", "class CreatePerson < Command\n  def call\n  end\nend\n")
      write(root, "app/legacy/old_query.rb", "class OldQuery\n  def call\n  end\nend\n")

      found = report(root).governed

      assert_includes found, "app/commands/create_person.rb"
      refute_includes found, "app/legacy/old_query.rb"
    end
  end

  def test_a_disabled_cop_measures_no_coupling
    in_repo(DISABLED_YML) do |root|
      write(root, "app/commands/create_person.rb", COMMAND)
      write(root, "app/queries/list_people.rb", QUERY)

      assert_equal 0, call(root)
    end
  end

  # `CouplingDelta` needs an edge's callee file, not just that it exists.
  def test_an_edge_names_its_caller_and_callee_files
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", COMMAND)
      write(root, "app/queries/list_people.rb", QUERY)

      edge = report(root).edges.first

      assert_equal "app/commands/create_person.rb", edge.caller
      assert_equal "app/queries/list_people.rb", edge.callee
    end
  end

  # A nested `.rubocop.yml` shifts the base dir for its own subtree, as `test/canaries/` does.
  def test_a_nested_config_does_not_lose_its_own_governed_files
    in_repo(RUBOCOP_YML) do |root|
      write(root, "sandbox/.rubocop.yml", "inherit_from:\n  - ../.rubocop.yml\n")
      write(root, "sandbox/app/commands/create_person.rb", COMMAND)
      write(root, "sandbox/app/queries/list_people.rb", QUERY)

      found = Shipshape::Coupling.new(directory: root, config: nil).call

      assert_includes found.governed, "sandbox/app/commands/create_person.rb"
      assert_includes found.governed, "sandbox/app/queries/list_people.rb"

      edge = found.edges.find { |e| e.caller == "sandbox/app/commands/create_person.rb" }
      refute_nil edge, "the caller under the nested config must still be a recorded edge"
      assert_equal "sandbox/app/queries/list_people.rb", edge.callee
    end
  end

  # Mirrors `test/canaries/.rubocop.yml`: walked by `governed_under`, excluded from ordinary scan.
  UNKNOWN_COP_IN_NESTED_CONFIG_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false
      Exclude:
        - 'sandbox/**/*'

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
  YAML

  # Watched to fail: reddened with a raw `RuboCop::ValidationError` before `ConfigAt`.
  def test_a_nested_config_naming_an_unknown_cop_is_tolerated_and_named
    in_repo(UNKNOWN_COP_IN_NESTED_CONFIG_YML) do |root|
      write(root, "sandbox/.rubocop.yml", "Shipshape/RetiredCopName:\n  Enabled: true\n")
      write(root, "sandbox/app/commands/create_person.rb", COMMAND)

      found = Shipshape::Coupling.new(directory: root, config: nil, tolerate_unknown_cops: true).call

      assert_includes found.skipped_cops, "Shipshape/RetiredCopName"
      assert_includes found.governed, "sandbox/app/commands/create_person.rb"
    end
  end

  # Without tolerance, a real mistake in the CURRENT tree's config must not be laundered away.
  def test_a_nested_config_naming_an_unknown_cop_still_raises_without_tolerance
    in_repo(UNKNOWN_COP_IN_NESTED_CONFIG_YML) do |root|
      write(root, "sandbox/.rubocop.yml", "Shipshape/RetiredCopName:\n  Enabled: true\n")
      write(root, "sandbox/app/commands/create_person.rb", COMMAND)

      assert_raises(RuboCop::ValidationError) do
        Shipshape::Coupling.new(directory: root, config: nil).call
      end
    end
  end

  # A cache bucket of its own: a file `BaseTestClassLines` already cached, marker-free, must
  # still show its coupling here - the shared-bucket bug this reddens if reverted.
  def test_a_file_the_line_ratchet_already_cached_still_reports_its_coupling
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/commands/create_person.rb", COMMAND)
      write(root, "app/queries/list_people.rb", QUERY)

      with_fresh_cache_root do
        Shipshape::BaseTestClassLines.new(directory: root, config: File.join(root, ".rubocop.yml")).call

        assert_equal 1, call(root)
      end
    end
  end

  private

  def call(root)
    coupling = Shipshape::Coupling.new(directory: root, config: File.join(root, ".rubocop.yml"))

    cold = coupling.call
    warm = coupling.call

    # A parallel run's files come back in whatever order the workers finished, not the order
    # they were dispatched in - `tally`, not `==`, is what "the same edges" means here.
    assert_equal cold.edges.tally, warm.edges.tally,
                 "a second, warm-cache run over the same directory must agree with the first"
    assert_equal cold.governed, warm.governed

    warm.edges.length
  end

  def report(root)
    Shipshape::Coupling.new(directory: root, config: File.join(root, ".rubocop.yml")).call
  end

  def write(root, path, contents)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end

  def with_fresh_cache_root
    was = ENV["RUBOCOP_CACHE_ROOT"]

    Dir.mktmpdir("shipshape-rubocop-cache") do |cache_root|
      ENV["RUBOCOP_CACHE_ROOT"] = cache_root
      yield
    end
  ensure
    ENV["RUBOCOP_CACHE_ROOT"] = was
  end

  # RUBYOPT puts the gem on the subprocess's load path; `companion.rb` is the second
  # inspectable file that turns `--parallel` on.
  def in_repo(config)
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip

    Dir.mktmpdir("shipshape-coupling") do |root|
      File.write(File.join(root, ".rubocop.yml"), config)
      write(root, "companion.rb", "class Companion\nend\n")
      yield(root)
    end
  ensure
    ENV["RUBYOPT"] = was
  end
end
