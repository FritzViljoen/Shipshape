# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "shipshape/error"
require "shipshape/git"
require "shipshape/base_test_class_lines"
require "shipshape/config_at"
require "shipshape/coupling"
require "shipshape/coupling_delta"
require "shipshape/coverage"
require "shipshape/guards"
require "shipshape/offences"
require "shipshape/renamed_paths"
require "shipshape/settings"
require "shipshape/typed_arguments"

module Shipshape
  # The ratchet: each cop's offences, failing where they rose - and the population of every
  # retiring kind, reported but never gated on, since `the-call-graph-is-declared` calls that
  # a curve, not a ratchet. No checked-in baseline: a regenerate button on a red build erases it.
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
      lines_after = BaseTestClassLines.new(directory: root, config: resolved).call
      coupling_after = Coupling.new(directory: root, config: resolved).call
      after, after_skips = population(root)

      base, lived, before_skips, lines_before, coupling_before, base_skips = git.at(sha) do |path|
        base_offences, base_config = measure_base(path)
        base_lines = BaseTestClassLines.new(directory: path, config: base_config, tolerate_unknown_cops: true)
        base_coupling = Coupling.new(directory: path, config: base_config, tolerate_unknown_cops: true)

        base_offences_result = base_offences.call
        base_population, base_population_skips = population(path, tolerate: true)
        base_lines_result = base_lines.call
        base_coupling_result = base_coupling.call

        [base_offences_result, base_population, base_population_skips, base_lines_result, base_coupling_result,
         base_offences.skipped_cops + base_lines.skipped_cops + base_coupling_result.skipped_cops]
      end

      coupling = CouplingDelta.new(base: coupling_before, head: coupling_after, renames: renames).call
      skipped = (after_skips + before_skips + base_skips).uniq.sort

      report(base: base, head: head, off: off, sha: sha, before: lived, after: after,
             lines_before: lines_before, lines_after: lines_after, coupling: coupling, skipped_cops: skipped)
    end

    private

    attr_reader :root, :trunk, :git, :config

    def trunk_name
      @trunk_name ||= trunk || git.default_trunk
    end

    # Base path => its name at HEAD, so a moved file canonicalises onto one name before use.
    def renames
      @renames ||= RenamedPaths.new(root: root).call
    end

    def arrived_in(was, now)
      (was.keys + now.keys).uniq.sort.each_with_object({}) do |kind, rows|
        before = was.fetch(kind, 0)
        after = now.fetch(kind, 0)
        rows[kind] = { was: before, now: after } if after > before
      end
    end

    # A file the base tree never had is not growth: it has nothing to compare against, so its
    # size at HEAD becomes the new floor instead.
    def grown_files(was, now)
      now.each_with_object({}) do |(file, size), rows|
        next unless was.key?(file)

        before = was.fetch(file)
        rows[file] = { was: before, now: size } if size > before
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

      [Offences.new(directory: path, config: config && target, tolerate_unknown_cops: true), config && target]
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
    # Returns `[population_by_kind, skipped_cops]` - see `ConfigAt`.
    def population(path, tolerate: false)
      layout = ConfigAt.call(path, config: config_path_in(path), tolerate_unknown_cops: tolerate)
      settings = Settings.layout(layout.config)

      return [{}, layout.skipped_cops] if settings.retiring.empty?

      coverage_config = ConfigAt.call(path, config: config_path_in(path), tolerate_unknown_cops: tolerate)
      by_kind = Coverage.new(config: coverage_config.config, root: path).call.by_kind

      hash = settings.retiring.to_h { |kind| [kind, by_kind.fetch(kind, 0)] }
      [hash, (layout.skipped_cops + coverage_config.skipped_cops).uniq.sort]
    end

    def config_path_in(path)
      File.join(path, config || CONFIG)
    end

    ZERO_COUPLING = CouplingDelta::Totals.new(was: 0, now: 0, arrived_edges: 0, arrived_files: 0,
                                              left_edges: 0, left_files: 0).freeze

    # `before:`/`after:`: the loops below assign `was` and `now`, and reassign them.
    def report(base:, head:, off:, sha:, before: {}, after: {}, lines_before: {}, lines_after: {},
               coupling: ZERO_COUPLING, skipped_cops: [])
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
        retiring: arrived_in(before, after), growth: grown_files(lines_before, lines_after),
        coupling: { was: coupling.was, now: coupling.now,
                    arrived_edges: coupling.arrived_edges, arrived_files: coupling.arrived_files,
                    left_edges: coupling.left_edges, left_files: coupling.left_files },
        skipped_cops: skipped_cops }
    end
  end
end
