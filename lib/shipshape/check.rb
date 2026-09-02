# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "shipshape/error"
require "shipshape/git"
require "shipshape/coverage"
require "shipshape/guards"
require "shipshape/offences"
require "shipshape/base_test_class_lines"
require "shipshape/settings"
require "shipshape/typed_arguments"

module Shipshape
  # The ratchet: each cop's offences, and the population of every retiring kind, here and at the
  # merge base — failing where either rose. No checked-in baseline: a snapshot has a regenerate
  # button, and pressing it on a red build erases the signal.
  class Check
    include TypedArguments

    CONFIG = ".rubocop.yml"

    # The config must sit at the REPOSITORY ROOT: RuboCop resolves globs against the config's
    # own directory, so `tools/.rubocop.yml` silences every kind-scoped cop and prints
    # "nothing rose" — this gem's own flag producing the false clean it exists to warn about.
    def initialize(root:, trunk: nil, config: nil)
      @root = typed(root, String)
      @trunk = typed(trunk, String, allow_nil: true)
      @config = config && relative(typed(config, String))
      @git = Git.new(root: root)
    end

    def call
      raise Error, "shipshape: #{root} is not a git repository." unless git.repository?

      sha = git.merge_base(trunk_name)
      resolved = config && File.join(root, config)
      head_offences = Offences.new(directory: root, config: resolved)
      head = head_offences.call
      off = Guards.new(directory: root, config: resolved).call
      head_lines = BaseTestClassLines.new(directory: root, config: resolved).call

      base, lived, base_lines = git.at(sha) do |path|
        base_offences, base_config = measure_base(path)
        [base_offences.call, population(path), BaseTestClassLines.new(directory: path, config: base_config).call]
      end

      report(base: base, head: head, off: off, sha: sha, before: lived, after: population(root),
             lines_before: base_lines, lines_after: head_lines)
    end

    private

    attr_reader :root, :trunk, :git, :config

    def trunk_name
      @trunk_name ||= trunk || git.default_trunk
    end

    def arrived_in(was, now)
      (was.keys + now.keys).uniq.sort.each_with_object({}) do |kind, rows|
        before = was.fetch(kind, 0)
        after = now.fetch(kind, 0)
        rows[kind] = { was: before, now: after } if after > before
      end
    end

    def measure_base(path)
      chosen = config || CONFIG
      source = File.join(root, chosen)
      target = File.join(path, chosen)

      if File.file?(source)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
      end

      [Offences.new(directory: path, config: config && target), config && target]
    end

    def relative(path)
      base = File.expand_path(root)
      full = File.expand_path(path, root)
      inside = full.delete_prefix(base + "/")

      raise Error, "shipshape: --config must name a file inside #{root}, got #{path}" if inside == full
      raise Error, "shipshape: --config must sit at #{root}, not in a subdirectory: #{inside}" if inside.include?("/")

      inside
    end

    # A legacy door is correct code and raises nothing, so what ratchets is the population.
    def population(path)
      settings = Settings.layout(config_at(path))

      return {} if settings.retiring.empty?

      by_kind = Coverage.new(config: config_at(path), root: path).call.by_kind

      settings.retiring.to_h { |kind| [kind, by_kind.fetch(kind, 0)] }
    end

    def config_at(path)
      store = RuboCop::ConfigStore.new
      chosen = File.join(path, config || CONFIG)
      store.options_config = chosen if File.file?(chosen)
      store.for_dir(path)
    end

    # `before:`/`after:`: the loops below assign `was` and `now`, and reassign them.
    def report(base:, head:, off:, sha:, before: {}, after: {}, lines_before: {}, lines_after: {})
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

      { base: base, head: head, off: off, risen: risen, fallen: fallen, sha: sha, trunk: trunk_name,
        retiring: arrived_in(before, after), growth: arrived_in(lines_before, lines_after) }
    end
  end
end
