# frozen_string_literal: true

require "test_helper"
require "shipshape/co_change"
require "open3"
require "fileutils"

# A real repository, real commits, a real `git mv`. Stubbing the log would test the arithmetic
# and leave the part that goes wrong — whether `-M` actually fires, and in what order the
# lines come back. Watched to fail: returning `commit[:others]` unresolved for a rename
# reddens the rename test; dropping the `> cap` guard reddens the cap test; sorting the raw
# log oldest-first instead of newest-first reddens the chained-rename test.
class CoChangeTest < Minitest::Test
  def test_two_files_touched_together_are_a_pair
    in_repo do |root|
      write(root, "a.rb", "a")
      write(root, "b.rb", "b")
      commit(root, "together")

      report = Shipshape::CoChange.new(root: root).call

      pair = report.pairs.find { |p| p.a == "a.rb" && p.b == "b.rb" }
      refute_nil pair
      assert_equal 1, pair.shared
      assert_equal 1, pair.a_commits
      assert_equal 1, pair.b_commits
    end
  end

  def test_files_touched_apart_are_not_a_pair
    in_repo do |root|
      write(root, "a.rb", "a")
      commit(root, "a only")
      write(root, "b.rb", "b")
      commit(root, "b only")

      report = Shipshape::CoChange.new(root: root).call

      assert_empty report.pairs
      assert_equal 1, report.totals["a.rb"]
      assert_equal 1, report.totals["b.rb"]
    end
  end

  # `git mv` unchanged content is exactly what `-M` is built to detect; without it this
  # commit reads as a delete-and-add and the file's history under its old name is orphaned.
  def test_a_rename_carries_its_earlier_history_forward
    in_repo do |root|
      write(root, "old_name.rb", "class Thing\nend\n")
      write(root, "sibling.rb", "class Sibling\nend\n")
      commit(root, "add both")

      write(root, "old_name.rb", "class Thing\n  def call; end\nend\n")
      write(root, "sibling.rb", "class Sibling\n  def call; end\nend\n")
      commit(root, "change both")

      git!(root, "mv", "old_name.rb", "new_name.rb")
      commit(root, "rename")

      report = Shipshape::CoChange.new(root: root).call

      assert_equal 3, report.totals["new_name.rb"],
        "the two commits under old_name.rb plus the rename commit itself"
      assert_equal 0, report.totals["old_name.rb"]

      pair = report.pairs.find { |p| p.a == "new_name.rb" && p.b == "sibling.rb" }
      refute_nil pair
      assert_equal 2, pair.shared,
        "the shared commit before the rename must still count under the new name"
    end
  end

  # A -> B -> C in three separate commits: everything must land on C, the one name that
  # exists at HEAD, however many times it was renamed on the way there.
  def test_a_chain_of_renames_resolves_to_the_final_name
    in_repo do |root|
      write(root, "name_a.rb", "1")
      commit(root, "add")

      git!(root, "mv", "name_a.rb", "name_b.rb")
      commit(root, "first rename")

      git!(root, "mv", "name_b.rb", "name_c.rb")
      commit(root, "second rename")

      report = Shipshape::CoChange.new(root: root).call

      assert_equal 3, report.totals["name_c.rb"]
      assert_equal 0, report.totals["name_a.rb"]
      assert_equal 0, report.totals["name_b.rb"]
    end
  end

  def test_a_commit_past_the_cap_contributes_no_pair
    in_repo do |root|
      names = (1..5).map { |n| "file_#{n}.rb" }
      names.each { |name| write(root, name, name) }
      commit(root, "five at once")

      report = Shipshape::CoChange.new(root: root, cap: 4).call

      assert_empty report.pairs
      names.each { |name| assert_equal 1, report.totals[name] }
    end
  end

  def test_a_commit_within_the_cap_still_pairs
    in_repo do |root|
      names = (1..4).map { |n| "file_#{n}.rb" }
      names.each { |name| write(root, name, name) }
      commit(root, "four at once")

      report = Shipshape::CoChange.new(root: root, cap: 4).call

      assert_equal names.length * (names.length - 1) / 2, report.pairs.length
    end
  end

  def test_ratio_is_against_the_less_changed_file
    in_repo do |root|
      write(root, "busy.rb", "1")
      write(root, "quiet.rb", "1")
      commit(root, "together")

      3.times do |n|
        write(root, "busy.rb", n.to_s)
        commit(root, "busy alone #{n}")
      end

      report = Shipshape::CoChange.new(root: root).call
      pair = report.pairs.find { |p| p.a == "busy.rb" && p.b == "quiet.rb" }

      assert_in_delta 1.0, pair.ratio
    end
  end

  def test_not_a_git_repository_raises
    Dir.mktmpdir("shipshape-not-a-repo") do |root|
      assert_raises(Shipshape::Error) { Shipshape::CoChange.new(root: root).call }
    end
  end

  private

  def in_repo
    Dir.mktmpdir("shipshape-cochange") do |root|
      git!(root, "init", "--quiet", "-b", "trunk")
      git!(root, "config", "user.email", "test@example.com")
      git!(root, "config", "user.name", "test")

      yield(root)
    end
  end

  def write(root, path, contents)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  def commit(root, message)
    git!(root, "add", "-A")
    git!(root, "commit", "--quiet", "-m", message)
  end

  def git!(root, *arguments)
    _, err, status = Open3.capture3("git", "-C", root, *arguments)
    raise "git #{arguments.first}: #{err}" unless status.success?
  end
end
