# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "shipshape/error"
require "shipshape/git"
require "shipshape/offences"
require "shipshape/typed_arguments"

module Shipshape
  # The ratchet. Counts each cop's offences here and at the commit this branch diverged
  # from, and fails only where a count **rose**.
  #
  # **There is no checked-in baseline file.** A snapshot of existing violations has a
  # regenerate button, and pressing it on a red build is exactly what erases the signal the
  # guard existed to raise. The baseline is derived from version control on every run.
  #
  # **Both trees are measured with the head tree's configuration.** That is the one place
  # this departs from "measure each tree as it was", and deliberately: with the base tree's
  # own config, enabling a cop would find its offences in head and none in base, so every
  # one would count as new and turning a cop on would be a five-hundred-offence event. With
  # the head config in both, enabling a cop is free and holds the line from that moment.
  # What is measured is therefore the effect of the CODE change, which is the question
  # anybody actually has.
  class Check
    include TypedArguments

    CONFIG = ".rubocop.yml"

    # **`config` is an escape from the application's own `.rubocop.yml`**, which on a legacy
    # repository is frequently unloadable here: it `require:`s plugins pinned to RuboCop 0.x,
    # which cannot be activated beside the 1.x this gem needs. Given one, both trees are
    # measured with that file and the application's config is never read.
    #
    # **It must sit at the repository root, and "inside the repository" is not enough.**
    # RuboCop resolves a config's globs against that config's own directory whenever its
    # basename starts with `.rubocop`, so `tools/.rubocop.yml` makes every `Kinds` glob match
    # nothing: the Style cops still fire, every kind-scoped cop goes silent, and `check` prints
    # "nothing rose". That is the false clean this gem exists to warn about, produced by its own
    # flag — and checking only for containment let it through.
    def initialize(root:, trunk: nil, config: nil)
      @root = typed(root, String)
      @trunk = typed(trunk, String, allow_nil: true)
      @config = config && relative(typed(config, String))
      @git = Git.new(root: root)
    end

    # Answers a report: { base:, head:, risen:, fallen:, sha:, trunk: }.
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

    # The head tree's config is copied in before measuring, so both runs are judged by the
    # same rules. Only the root config is copied: a config that inherits from a file
    # elsewhere in the repository gets that file from the BASE commit, which is a stated
    # limit rather than a silent one.
    # The chosen config is copied to the same relative place in the base tree, so its globs
    # resolve against a tree root in both runs rather than against two different directories.
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

    # The file's name inside the repository, refusing anything that would resolve its globs
    # somewhere other than the tree root.
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
