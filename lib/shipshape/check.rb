# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "shipshape/error"
require "shipshape/git"
require "shipshape/offences"
require "shipshape/typed_arguments"

module Shipshape
  # The ratchet: each cop's offences here and at the merge base, failing only where a count rose.
  # No checked-in baseline — a snapshot has a regenerate button, and pressing it on a red build
  # erases the signal. Both trees use the head config, so enabling a cop is free.
  class Check
    include TypedArguments

    CONFIG = ".rubocop.yml"

    # The config must sit at the REPOSITORY ROOT: RuboCop resolves a config's globs against its
    # own directory, so `tools/.rubocop.yml` silences every kind-scoped cop and prints
    # "nothing rose" — the false clean this gem exists to warn about, from its own flag.
    def initialize(root:, trunk: nil, config: nil)
      @root = typed(root, String)
      @trunk = typed(trunk, String, allow_nil: true)
      @config = config && relative(typed(config, String))
      @git = Git.new(root: root)
    end

      def call
      raise Error, "shipshape: #{root} is not a git repository." unless git.repository?

      sha = git.merge_base(trunk_name)
      head = Offences.new(directory: root, config: config && File.join(root, config)).call
      base = git.at(sha) { |path| measure_base(path) }

      report(base: base, head: head, sha: sha)
    end

    private

    attr_reader :root, :trunk, :git, :config

    def trunk_name
      @trunk_name ||= trunk || git.default_trunk
    end

    def measure_base(path)
      chosen = config || CONFIG
      source = File.join(root, chosen)
      target = File.join(path, chosen)

      if File.file?(source)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
      end

      Offences.new(directory: path, config: config && target).call
    end

    def relative(path)
      base = File.expand_path(root)
      full = File.expand_path(path, root)
      inside = full.delete_prefix(base + "/")

      raise Error, "shipshape: --config must name a file inside #{root}, got #{path}" if inside == full
      raise Error, "shipshape: --config must sit at #{root}, not in a subdirectory: #{inside}" if inside.include?("/")

      inside
    end

    def report(base:, head:, sha:)
      cops = (base.keys + head.keys).uniq.sort

      risen = cops.each_with_object({}) do |cop, rows|
        was = base.fetch(cop, 0)
        now = head.fetch(cop, 0)
        rows[cop] = { was: was, now: now } if now > was
      end

      fallen = cops.each_with_object({}) do |cop, rows|
        was = base.fetch(cop, 0)
        now = head.fetch(cop, 0)
        rows[cop] = { was: was, now: now } if now < was
      end

      { base: base, head: head, risen: risen, fallen: fallen, sha: sha, trunk: trunk_name }
    end
  end
end
