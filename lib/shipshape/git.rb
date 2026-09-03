# frozen_string_literal: true

require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # The only place that shells out to git, always through an argument array and never a shell
  # string: a branch name holding a semicolon or a backtick is an argument, not a command.
  class Git
    include TypedArguments

    def initialize(root:)
      @root = typed(root, String)
    end

    # The merge base, not the tip: an offence added to the trunk after you branched is not
    # yours, and comparing against the tip would hand you their bill.
    def merge_base(trunk)
      run("merge-base", "HEAD", typed(trunk, String)).strip
    end

    def default_trunk
      run("rev-parse", "--abbrev-ref", "origin/HEAD").strip
    rescue Error
      raise Error, "shipshape: no origin/HEAD. Name the trunk with --trunk, or run " \
                   "`git remote set-head origin --auto`."
    end

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
