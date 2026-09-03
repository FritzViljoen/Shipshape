# frozen_string_literal: true

require "test_helper"
require "shipshape/co_change"
require "open3"

# See docs/laws/co-change-is-a-fact-not-a-verdict.md, "safe ... including a linked worktree".
class CoChangeWorktreeTest < Minitest::Test
  WORKTREE = File.expand_path("../..", __dir__)

  def test_a_linked_worktree_reports_the_same_history_as_its_main_checkout
    skip "not run from a linked worktree" unless File.file?(File.join(WORKTREE, ".git"))

    common = File.read(File.join(WORKTREE, ".git"))[/gitdir: (.*)\/\.git\/worktrees/, 1]
    skip "no sibling main checkout found" unless common && File.directory?(File.join(common, ".git"))

    ref, err, status = Open3.capture3("git", "-C", WORKTREE, "merge-base", "HEAD", "origin/main") # a sha both name
    skip "no shared ancestor with origin/main: #{err}" unless status.success?

    from_worktree = Shipshape::CoChange.new(root: WORKTREE, ref: ref.strip).call
    from_main = Shipshape::CoChange.new(root: common, ref: ref.strip).call

    assert_equal from_main.commits, from_worktree.commits
    assert_equal from_main.totals, from_worktree.totals
    assert_equal from_main.pairs, from_worktree.pairs
  end
end
