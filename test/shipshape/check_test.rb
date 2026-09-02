# frozen_string_literal: true

require "test_helper"
require "shipshape/check"
require "open3"
require "fileutils"

# A real repository, two real commits, two real RuboCop runs. Stubbing any of it would test
# the arithmetic and leave the part that goes wrong — the worktree, the config copy, the JSON.
# Watched to fail: returning `{}` from `population` reddens the retiring test. Returning `{}`
# from `lines_of` reddens the growth test below it; reverting `Offences#call` to discard the
# per-file grouping reddens it too, since `paths_for` would have nothing left to read.
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

  def test_a_base_test_class_that_grew_is_refused
    in_growth_repo(baseline: BASE_TEST_CASE) do |root|
      write(root, "test/support/admin_test_case.rb", GROWN_BASE_TEST_CASE)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal({ was: 3, now: 5 }, report[:growth]["test/support/admin_test_case.rb"])
      assert_equal({ was: 1, now: 2 }, report[:risen]["Shipshape/BaseTestClassGrowth"],
        "the definition count is the existing per-cop offence ratchet, unchanged")
    end
  end

  def test_a_base_test_class_that_did_not_grow_is_not_refused
    in_growth_repo(baseline: BASE_TEST_CASE) do |root|
      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:growth]
      assert_empty report[:risen]
    end
  end

  def test_a_leaf_test_growing_is_not_the_ratchets_business
    in_growth_repo(path: "test/support/admin_test_case_test.rb", baseline: BASE_TEST_CASE) do |root|
      write(root, "test/support/admin_test_case_test.rb", GROWN_BASE_TEST_CASE)

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:growth], "a file named like a leaf test is excluded, not ratcheted"
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

  # A repository with no operations at all — `Shipshape/BaseTestClassGrowth` needs none, and
  # this proves it: `Shipshape/CallGraph`'s Kinds fall back to the gem's own defaults, which
  # name paths nothing here uses, so the retiring machinery stays empty and silent.
  def in_growth_repo(path: "test/support/admin_test_case.rb", baseline:)
    with_gem_on_the_load_path do
      Dir.mktmpdir("shipshape-repo") do |root|
        git!(root, "init", "--quiet", "-b", "trunk")
        git!(root, "config", "user.email", "test@example.com")
        git!(root, "config", "user.name", "test")

        write(root, ".rubocop.yml", GROWTH_YML)
        write(root, path, baseline)

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
