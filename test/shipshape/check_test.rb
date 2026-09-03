# frozen_string_literal: true

require "test_helper"
require "shipshape/check"
require "open3"
require "fileutils"

# A real repository, two real commits, two real RuboCop runs. Stubbing any of it would test
# the arithmetic and leave the part that goes wrong — the worktree, the config copy, the JSON.
# Watched to fail: returning `{}` from `population` reddens the retiring test; reverting
# `Offences#call` to discard the per-file grouping reddens it too, since `paths_for` would have
# nothing left to read.
class CheckTest < Minitest::Test
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

    Shipshape/OneOperationOneClass:
      Enabled: false
  YAML

  CLEAN_COMMAND = "class CreatePerson < Command\n  def call\n    ListPeople.call\n  end\nend\n"
  DIRTY_QUERY = "class ListPeople < Query\n  def call\n    Other.call\n  end\nend\n"
  OTHER_QUERY = "class Other < Query\n  def call\n    []\n  end\nend\n"

  def test_nothing_rose_when_nothing_changed
    in_repo do |root|
      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen]
      assert_empty report[:fallen]
    end
  end

  # The whole point. A branch that adds a violation is refused; the pile it inherited is not
  # its bill.
  def test_a_new_violation_is_refused
    in_repo do |root|
      write(root, "app/queries/list_people.rb", DIRTY_QUERY)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal({ was: 0, now: 1 }, report[:risen]["Shipshape/CallGraph"])
    end
  end

  def test_an_inherited_pile_is_not_the_branch_s_bill
    in_repo(baseline: DIRTY_QUERY) do |root|
      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen]
      assert_equal 1, report[:head]["Shipshape/CallGraph"],
        "An inherited pile is survivable, which is the only reason this can be installed on a legacy application at all."
    end
  end

  def test_a_count_that_fell_is_reported_and_becomes_the_floor
    in_repo(baseline: DIRTY_QUERY) do |root|
      write(root, "app/queries/list_people.rb", "class ListPeople < Query\n  def call\n    []\n  end\nend\n")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen]
      assert_equal({ was: 1, now: 0 }, report[:fallen]["Shipshape/CallGraph"])
    end
  end

  def test_enabling_a_cop_on_the_branch_is_free
    in_repo(baseline: DIRTY_QUERY, config: RUBOCOP_YML.sub("Shipshape/CallGraph:", "Shipshape/CallGraph:\n  Enabled: false\n")) do |root|
      write(root, ".rubocop.yml", format(RUBOCOP_YML, gem: gem_root))

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen], "enabling a cop should not bill the branch for old code"
      assert_equal 1, report[:head]["Shipshape/CallGraph"]
      assert_equal 1, report[:base]["Shipshape/CallGraph"],
        "Both trees are measured with the HEAD tree's config. Without that, turning a cop on would find its offences in head and none in base, and enabling a cop would be a five-hundred-offence event on any real application."
      assert_includes report[:off], "Shipshape/OneOperationOneClass"
      refute_includes report[:off], "Shipshape/CallGraph",
        "off is read from the branch's own config, not the trunk's — the branch re-enabled this one"
    end
  end

  # The baseline already has CreatePerson calling ListPeople; the branch inherits it untouched.
  def test_coupling_is_flat_when_nothing_changed
    in_repo do |root|
      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal report[:coupling][:was], report[:coupling][:now]
    end
  end

  # A brand new file is a new floor, not a rise - `CreatePerson` already exists.
  def test_coupling_rises_with_a_new_call
    in_repo do |root|
      write(root, "app/commands/create_person.rb",
            "class CreatePerson < Command\n  def call\n    ListPeople.call\n    Other.call\n  end\nend\n")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_operator report[:coupling][:now], :>, report[:coupling][:was]
    end
  end

  # It reads `0 -> 0`: identity is a path, so the old caller leaves governance and the new
  # path arrives - two edges cancelling, the guard's own stated limit, not one holding still.
  def test_a_pure_file_move_leaves_coupling_flat
    in_repo do |root|
      moved = File.join(root, "app/commands/people/create_person.rb")
      FileUtils.mkdir_p(File.dirname(moved))
      FileUtils.mv(File.join(root, "app/commands/create_person.rb"), moved)
      git!(root, "add", "-A")
      git!(root, "commit", "--quiet", "-m", "move create_person.rb, touch no call")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal report[:coupling][:was], report[:coupling][:now]
      assert_equal 1, report[:coupling][:arrived_edges]
      assert_equal 1, report[:coupling][:arrived_files]
      assert_equal 1, report[:coupling][:left_edges]
      assert_equal 1, report[:coupling][:left_files]
    end
  end

  # A legacy caller brought under governance reports as an arrival, never a rise.
  def test_moving_a_file_into_governance_does_not_rise
    in_repo do |root|
      write(root, "app/legacy/old_query.rb",
            "class OldQuery < Command\n  def call\n    CreatePerson.call(name: \"x\")\n  end\nend\n")
      git!(root, "add", "-A")
      git!(root, "commit", "--quiet", "-m", "add an ungoverned legacy caller")

      moved = File.join(root, "app/commands/old_query.rb")
      FileUtils.mv(File.join(root, "app/legacy/old_query.rb"), moved)
      git!(root, "add", "-A")
      git!(root, "commit", "--quiet", "-m", "move old_query.rb under governance, touch no call")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal report[:coupling][:was], report[:coupling][:now]
      assert_equal 1, report[:coupling][:arrived_edges]
      assert_equal 1, report[:coupling][:arrived_files]
      assert_equal 0, report[:coupling][:left_edges]
    end
  end

  # The reviewer's case B: a cut alongside an ungoverned file arriving with real calls.
  # The old intersection reported `{was: 2, now: 1}` and said nothing about the 3 that arrived.
  def test_a_cut_and_an_arriving_file_are_never_reported_as_one_number
    custom_repo({
      "app/commands/create_person.rb" =>
        "class CreatePerson < Command\n  def call\n    ListPeople.call\n    Other.call\n  end\nend\n",
      "app/queries/list_people.rb" => OTHER_QUERY,
      "app/queries/other.rb" => OTHER_QUERY,
      "app/legacy/big.rb" =>
        "class Big\n  def call\n    ListPeople.call\n    ListPeople.call\n    ListPeople.call\n  end\nend\n",
    }) do |root|
      write(root, "app/commands/create_person.rb", "class CreatePerson < Command\n  def call\n    ListPeople.call\n  end\nend\n")
      FileUtils.mv(File.join(root, "app/legacy/big.rb"), File.join(root, "app/commands/big.rb"))

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal 2, report[:coupling][:was]
      assert_equal 1, report[:coupling][:now], "the real cut is not hidden by the file that arrived"
      assert_equal 3, report[:coupling][:arrived_edges]
      assert_equal 1, report[:coupling][:arrived_files]
      assert_equal 0, report[:coupling][:left_edges]
    end
  end

  def test_a_cut_call_makes_coupling_fall
    in_repo do |root|
      write(root, "app/commands/create_person.rb", "class CreatePerson < Command\n  def call\n  end\nend\n")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_operator report[:coupling][:now], :<, report[:coupling][:was]
    end
  end

  def test_it_leaves_the_working_copy_alone
    in_repo do |root|
      write(root, "app/queries/list_people.rb", DIRTY_QUERY)
      Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal DIRTY_QUERY, File.read(File.join(root, "app/queries/list_people.rb"))
      assert_empty capture(root, "worktree", "list", "--porcelain").scan(/^worktree/).drop(1),
        "The working copy is never checked out, moved or stashed. A tool that disturbs the tree to measure it is one nobody runs twice."
    end
  end

  def test_an_explicit_config_is_used_for_both_trees
    in_repo(baseline: DIRTY_QUERY) do |root|
      write(root, ".rubocop-shipshape.yml", format(RUBOCOP_YML, gem: gem_root))
      # The repository's own config is removed, so anything found came from the given one.
      FileUtils.rm(File.join(root, ".rubocop.yml"))

      report = Shipshape::Check.new(root: root, trunk: "trunk", config: ".rubocop-shipshape.yml").call

      assert_equal 1, report[:head]["Shipshape/CallGraph"], "head did not use the given config"
      assert_equal 1, report[:base]["Shipshape/CallGraph"],
                   "the base tree did not use the given config: --config has to reach both " \
                   "trees, or the comparison is between two different rulebooks"
    end
  end

  # **A config in a subdirectory is the dangerous half-working case.** RuboCop resolves a
  # config's globs against its own directory when the basename starts with `.rubocop`, so
  # `tools/.rubocop.yml` leaves every kind-scoped cop silent while the Style cops still fire —
  # and `check` prints "nothing rose" over a run that inspected nothing.
  def test_a_config_in_a_subdirectory_is_refused
    in_repo do |root|
      write(root, "tools/.rubocop.yml", format(RUBOCOP_YML, gem: gem_root))

      error = assert_raises(Shipshape::Error) do
        Shipshape::Check.new(root: root, trunk: "trunk", config: "tools/.rubocop.yml").call
      end

      assert_includes error.message, "not in a subdirectory"
    end
  end

  def test_a_config_outside_the_repository_is_refused
    in_repo do |root|
      outside = File.join(Dir.mktmpdir("shipshape-outside"), ".rubocop.yml")
      File.write(outside, format(RUBOCOP_YML, gem: gem_root))

      error = assert_raises(Shipshape::Error) do
        Shipshape::Check.new(root: root, trunk: "trunk", config: outside).call
      end

      assert_includes error.message, "must name a file inside",
        "**A config outside the repository cannot work and must not half-work.** Same cause, one step further out: nothing in the base tree would resolve against a tree root at all."
    end
  end

  def test_a_directory_that_is_not_a_repository_says_so
    Dir.mktmpdir("shipshape-none") do |root|
      error = assert_raises(Shipshape::Error) { Shipshape::Check.new(root: root).call }

      assert_includes error.message, "not a git repository",
        "Watched to fail: passing the config to head only reddens the assertion above, because the base tree falls back to the unloadable one and reports nothing."
    end
  end

  # A legacy door is correct code and raises nothing, so the offence counts cannot see one
  # filling up. What ratchets is the population: a file arriving there is a refactor moving code
  # into a kind already on its way out, which is how a migration stops half way.
  def test_a_file_arriving_in_a_retiring_kind_is_refused
    in_repo(config: RETIRING_YML) do |root|
      FileUtils.mkdir_p(File.join(root, "app/legacy"))
      write(root, "app/legacy/find_person_legacy.rb",
            "class FindPersonLegacy < LegacyQuery\n  def call\n    []\n  end\nend\n")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal({ "legacy_query" => { was: 0, now: 1 } }, report[:retiring])
    end
  end

  def test_a_kind_that_is_not_retiring_is_not_counted
    in_repo(config: RETIRING_YML) do |root|
      write(root, "app/queries/another.rb", OTHER_QUERY.sub("Other", "Another"))

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:retiring], "only a kind declared on its way out ratchets by population"
    end
  end

  def test_a_grown_base_test_class_is_refused
    in_growth_repo(baseline: BASE_TEST_CASE) do |root|
      write(root, "test/support/admin_test_case.rb", GROWN_BASE_TEST_CASE)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal({ was: 1, now: 2 }, report[:risen]["Shipshape/BaseTestClassGrowth"])
    end
  end

  def test_a_base_test_class_that_did_not_grow_is_not_refused
    in_growth_repo(baseline: BASE_TEST_CASE) do |root|
      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen]
    end
  end

  # A concern loaded by the engine's own dummy app is not this law's business.
  def test_a_dummy_app_concern_is_not_the_ratchets_business
    in_growth_repo(baseline: BASE_TEST_CASE) do |root|
      write(root, "test/dummy/app/models/concerns/payable.rb", "module Payable\n  def total\n    1\n  end\nend\n")

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen]
    end
  end

  # The repro a reviewer ran: the two numbers used to share a gate.
  def test_a_golfed_base_test_class_still_grows_by_line_count
    in_growth_repo(baseline: BASE_TEST_CASE) do |root|
      write(root, "test/support/admin_test_case.rb", GOLFED_BASE_TEST_CASE)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal({ was: 1, now: 0 }, report[:fallen]["Shipshape/BaseTestClassGrowth"],
        "the definition count on its own reads this as an improvement")
      assert_equal({ was: 3, now: 7 }, report[:growth]["test/support/admin_test_case.rb"],
        "the line count catches what the definition count's fall hid")
    end
  end

  # `shipshape install` writes the base class `check` has never seen before; a file the merge
  # base does not have is not growth on that file, because there is nothing to compare against.
  def test_a_new_base_test_class_file_is_not_growth
    in_growth_repo(baseline: nil) do |root|
      write(root, "test/support/admin_test_case.rb", BASE_TEST_CASE)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:growth]
    end
  end

  def test_a_disabled_base_test_class_growth_measures_no_growth
    in_growth_repo(baseline: BASE_TEST_CASE, config: DISABLED_GROWTH_YML) do |root|
      write(root, "test/support/admin_test_case.rb", GROWN_BASE_TEST_CASE)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:growth]
    end
  end

  private

  def gem_root
    File.expand_path("../..", __dir__)
  end

  # A repository with a `trunk` branch holding `baseline`, and a branch on top of it.
  #
  # RuboCop runs as a subprocess, so it needs the gem on its load path the way a real
  # consumer would have it from the Gemfile. RUBYOPT is how that is said to a child process
  # without teaching Offences a test-only argument.
  RETIRING_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        command: ['app/commands/**/*.rb']
        query: ['app/queries/**/*.rb']
        legacy_query: ['app/legacy/**/*_legacy.rb']
      Retiring:
        - legacy_query
      BaseClasses:
        command: [Command]
        query: [Query]
        legacy_query: [LegacyQuery]
      Sisters:
        - [command]
        - [query, legacy_query]
      Matrix:
        command: [query, legacy_query]
        query: []
        legacy_query: []
  YAML

  GROWTH_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false
  YAML

  BASE_TEST_CASE = <<~RUBY
    class AdminTestCase < ActiveSupport::TestCase
      def sign_in_as_admin; end
    end
  RUBY

  GROWN_BASE_TEST_CASE = <<~RUBY
    class AdminTestCase < ActiveSupport::TestCase
      def sign_in_as_admin; end

      def travel_to(time); end
    end
  RUBY

  # None of this is a definition `BaseTestClassGrowth` counts, so the offence count *falls*.
  GOLFED_BASE_TEST_CASE = <<~RUBY
    class AdminTestCase < ActiveSupport::TestCase
      logger.info("line one")
      logger.info("line two")
      logger.info("line three")
      logger.info("line four")
      logger.info("line five")
    end
  RUBY

  DISABLED_GROWTH_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/BaseTestClassGrowth:
      Enabled: false
  YAML

  # A repository with no operations at all — `Shipshape/BaseTestClassGrowth` needs none, and
  # this proves it: `Shipshape/CallGraph`'s Kinds fall back to the gem's own defaults, which
  # name paths nothing here uses, so the retiring machinery stays empty and silent.
  #
  # `companion.rb` is the second inspectable file that turns RuboCop's own `--parallel` on.
  def in_growth_repo(path: "test/support/admin_test_case.rb", baseline:, config: GROWTH_YML)
    with_gem_on_the_load_path do
      Dir.mktmpdir("shipshape-repo") do |root|
        git!(root, "init", "--quiet", "-b", "trunk")
        git!(root, "config", "user.email", "test@example.com")
        git!(root, "config", "user.name", "test")

        write(root, ".rubocop.yml", config)
        write(root, "companion.rb", "class Companion\nend\n")
        write(root, path, baseline) if baseline

        git!(root, "add", "-A")
        git!(root, "commit", "--quiet", "-m", "baseline")
        git!(root, "checkout", "--quiet", "-b", "branch")

        yield(root)
      end
    end
  end

  def in_repo(baseline: OTHER_QUERY, config: nil)
    with_gem_on_the_load_path do
      in_repo_without_load_path(baseline: baseline, config: config) { |root| yield(root) }
    end
  end

  def with_gem_on_the_load_path
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip
    yield
  ensure
    ENV["RUBYOPT"] = was
  end

  def in_repo_without_load_path(baseline:, config:)
    Dir.mktmpdir("shipshape-repo") do |root|
      git!(root, "init", "--quiet", "-b", "trunk")
      git!(root, "config", "user.email", "test@example.com")
      git!(root, "config", "user.name", "test")

      write(root, ".rubocop.yml", format(config || RUBOCOP_YML, gem: gem_root))
      write(root, "app/commands/create_person.rb", CLEAN_COMMAND)
      write(root, "app/queries/other.rb", OTHER_QUERY)
      write(root, "app/queries/list_people.rb", baseline)

      git!(root, "add", "-A")
      git!(root, "commit", "--quiet", "-m", "baseline")
      git!(root, "checkout", "--quiet", "-b", "branch")

      yield(root)
    end
  end

  # A base commit made of exactly the files given, not `in_repo`'s fixed three.
  def custom_repo(files, config: nil)
    with_gem_on_the_load_path do
      Dir.mktmpdir("shipshape-repo") do |root|
        git!(root, "init", "--quiet", "-b", "trunk")
        git!(root, "config", "user.email", "test@example.com")
        git!(root, "config", "user.name", "test")

        write(root, ".rubocop.yml", format(config || RUBOCOP_YML, gem: gem_root))
        files.each { |path, contents| write(root, path, contents) }

        git!(root, "add", "-A")
        git!(root, "commit", "--quiet", "-m", "baseline")
        git!(root, "checkout", "--quiet", "-b", "branch")

        yield(root)
      end
    end
  end

  def write(root, path, contents)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  def git!(root, *arguments)
    _, err, status = Open3.capture3("git", "-C", root, *arguments)
    raise "git #{arguments.first}: #{err}" unless status.success?
  end

  def capture(root, *arguments)
    out, = Open3.capture3("git", "-C", root, *arguments)
    out
  end
end
