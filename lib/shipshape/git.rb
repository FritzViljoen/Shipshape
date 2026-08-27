# frozen_string_literal: true

require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # The only place that shells out to git.
  #
  # Every call goes through `Open3.capture3` with an argument array — never a shell string —
  # so a branch name containing a space, a semicolon or a backtick is an argument and not a
  # command. A double-quoted shell string is how a gate hook silently became a no-op in the
  # sibling repository, and this is the same hazard one layer down.
  class Git
    include TypedArguments

    def initialize(root:)
      @root = typed(root, String)
    end

    # The commit the branch diverged from. That, and not the tip of the trunk, is the right
    # baseline: an offence somebody else added to the trunk after you branched is not yours,
    # and comparing against the tip would hand you their bill.
    def merge_base(trunk)
      run("merge-base", "HEAD", typed(trunk, String)).strip
    end

    # `origin/HEAD` is what the remote says its default branch is, so nothing here has to
    # guess between main and master. A repository without it says so rather than being
    # guessed at.
    def default_trunk
      run("rev-parse", "--abbrev-ref", "origin/HEAD").strip
    rescue Error
      raise Error, "shipshape: no origin/HEAD. Name the trunk with --trunk, or run " \
                   "`git remote set-head origin --auto`."
    end

    # A detached worktree at one commit, removed afterwards whether or not the block raised.
    # The application's own tree is never checked out, moved or stashed — a tool that
    # disturbs the working copy to measure it is one nobody runs twice.
    def at(sha)
      path = Dir.mktmpdir("shipshape-base")
      run("worktree", "add", "--detach", "--quiet", path, typed(sha, String))

      begin
        yield(path)
      ensure
        run("worktree", "remove", "--force", path)
      end
    end

    def repository?
      run("rev-parse", "--git-dir")
      true
    rescue Error
      false
    end

    private

    attr_reader :root

    def run(*arguments)
      out, err, status = Open3.capture3("git", "-C", root, *arguments)
      raise Error, "shipshape: git #{arguments.first} failed: #{err.strip}" unless status.success?

      out
    end
  end
end
