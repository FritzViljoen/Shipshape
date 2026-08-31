# frozen_string_literal: true

require "test_helper"
require "shipshape/check"
require "open3"
require "fileutils"

# A real repository, two real commits, two real RuboCop runs. Stubbing any of it would test
# the arithmetic and leave the part that actually goes wrong — the worktree, the config
# copy, the JSON — unexercised.
#
# Watched to fail: making Check#report treat `now > was` as `now >= was` reddens the
# unchanged case; dropping the config copy in #measure_base reddens the
# enabling-a-cop-is-free case.
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

  # An inherited pile is survivable, which is the only reason this can be installed on a
  # legacy application at all.
  def test_an_inherited_pile_is_not_the_branch_s_bill
    in_repo(baseline: DIRTY_QUERY) do |root|
      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen]
      assert_equal 1, report[:head]["Shipshape/CallGraph"]
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

  # Both trees are measured with the HEAD tree's config. Without that, turning a cop on
  # would find its offences in head and none in base, and enabling a cop would be a
  # five-hundred-offence event on any real application.
  def test_enabling_a_cop_on_the_branch_is_free
    in_repo(baseline: DIRTY_QUERY, config: RUBOCOP_YML.sub("Shipshape/CallGraph:", "Shipshape/CallGraph:\n  Enabled: false\n")) do |root|
      write(root, ".rubocop.yml", format(RUBOCOP_YML, gem: gem_root))

      report = Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_empty report[:risen], "enabling a cop should not bill the branch for old code"
      assert_equal 1, report[:head]["Shipshape/CallGraph"]
      assert_equal 1, report[:base]["Shipshape/CallGraph"]
    end
  end

  # The working copy is never checked out, moved or stashed. A tool that disturbs the tree
  # to measure it is one nobody runs twice.
  def test_it_leaves_the_working_copy_alone
    in_repo do |root|
      write(root, "app/queries/list_people.rb", DIRTY_QUERY)
      Shipshape::Check.new(root: root, trunk: "trunk").call

      assert_equal DIRTY_QUERY, File.read(File.join(root, "app/queries/list_people.rb"))
      assert_empty capture(root, "worktree", "list", "--porcelain").scan(/^worktree/).drop(1)
    end
  end

  # **An application's own `.rubocop.yml` is frequently unloadable here**, because it
  # `require:`s plugins pinned to RuboCop 0.x, which cannot be activated beside the 1.x this
  # gem needs. Measured against a real legacy repository the run died in config loading before
  # reading a file, which reads like the gem not working. `--config` is the way out, and it
  # has to reach both trees or the comparison is between two different rulebooks.
  def test_an_explicit_config_is_used_for_both_trees
    in_repo(baseline: DIRTY_QUERY) do |root|
      write(root, "tools/shipshape.yml", format(RUBOCOP_YML, gem: gem_root))
      # The repository's own config is removed, so anything found came from the given one.
      FileUtils.rm(File.join(root, ".rubocop.yml"))

      report = Shipshape::Check.new(root: root, trunk: "trunk", config: "tools/shipshape.yml").call

      assert_equal 1, report[:head]["Shipshape/CallGraph"], "head did not use the given config"
      assert_equal 1, report[:base]["Shipshape/CallGraph"], "the base tree did not use the given config"
    end
  end

  # **A config outside the repository cannot work and must not half-work.** RuboCop resolves a
  # config's globs against its own directory, so an out-of-tree file leaves every kind-scoped
  # cop silent while the Style cops still fire — a clean run that inspected nothing.
  def test_a_config_outside_the_repository_is_refused
    in_repo do |root|
      outside = File.join(Dir.mktmpdir("shipshape-outside"), ".rubocop.yml")
      File.write(outside, format(RUBOCOP_YML, gem: gem_root))

      error = assert_raises(Shipshape::Error) do
        Shipshape::Check.new(root: root, trunk: "trunk", config: outside).call
      end

      assert_includes error.message, "must name a file inside"
    end
  end

  # Watched to fail: passing the config to head only reddens the assertion above, because the
  # base tree falls back to the unloadable one and reports nothing.
  def test_a_directory_that_is_not_a_repository_says_so
    Dir.mktmpdir("shipshape-none") do |root|
      error = assert_raises(Shipshape::Error) { Shipshape::Check.new(root: root).call }

      assert_includes error.message, "not a git repository"
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
