# frozen_string_literal: true

require "shipshape/error"
require "shipshape/git"
require "shipshape/typed_arguments"

module Shipshape
  # How often two files land in the same commit. Evidence only, same discipline as
  # `TableShapes` — see `docs/laws/co-change-is-a-fact-not-a-verdict.md`.
  class CoChange
    include TypedArguments

    # 500 files is 124,750 pairs from one mechanical commit alone; 50 stays clear of that
    # while still admitting a real multi-file slice. Only pairing is capped — a file's own
    # total in `totals` never depends on whether a commit it appeared in was too large to pair.
    DEFAULT_CAP = 50

    Pair = Struct.new(:a, :b, :shared, :a_commits, :b_commits, keyword_init: true) do
      # Against the busier file, not the sum: 90 of 661 is a loose tag-along; 90 of 95 is not.
      def ratio
        shared.to_f / [a_commits, b_commits].min
      end
    end

    Report = Struct.new(:pairs, :totals, :commits, :cap, keyword_init: true) do
      alias_method :churn, :totals
    end

    RENAME = /\AR/.freeze

    def initialize(root:, cap: DEFAULT_CAP, ref: "HEAD")
      @root = typed(root, String)
      @cap = typed(cap, Integer)
      @ref = typed(ref, String)
      @git = Git.new(root: root)
    end

    def call
      raise Error, "shipshape: #{root} is not a git repository." unless git.repository?

      commits = canonical_commits
      totals = Hash.new(0)
      shared = Hash.new(0)

      commits.each do |files|
        files.each { |file| totals[file] += 1 }
        pair_up(files, shared)
      end

      pairs = shared.map do |(a, b), count|
        Pair.new(a: a, b: b, shared: count, a_commits: totals[a], b_commits: totals[b])
      end.sort_by { |pair| [-pair.shared, pair.a, pair.b] }

      Report.new(pairs: pairs, totals: totals, commits: commits.length, cap: cap)
    end

    private

    attr_reader :root, :cap, :ref, :git

    def pair_up(files, shared)
      return if files.length < 2 || files.length > cap

      files.sort.combination(2).each { |a, b| shared[[a, b]] += 1 }
    end

    # Newest first: an older rename already resolves through `forward` in one lookup.
    def canonical_commits
      forward = {}

      raw_commits.map do |commit|
        touched = commit[:renames].map do |old, new|
          final = forward.fetch(new, new)
          forward[old] = final
          final
        end

        (touched + commit[:others].map { |name| forward.fetch(name, name) }).uniq
      end
    end

    def raw_commits
      commits = []

      git.name_status_log(ref: ref).each_line(chomp: true) do |line|
        if line == "COMMIT"
          commits << { renames: [], others: [] }
        elsif !line.empty?
          record(commits.last, line)
        end
      end

      commits
    end

    def record(commit, line)
      status, *paths = line.split("\t")

      if status.match?(RENAME)
        commit[:renames] << [paths[0], paths[1]]
      else
        commit[:others] << paths[0]
      end
    end
  end
end
