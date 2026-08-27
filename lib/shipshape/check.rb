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

    def initialize(root:, trunk: nil)
      @root = typed(root, String)
      @trunk = typed(trunk, String, allow_nil: true)
      @git = Git.new(root: root)
    end

    # Answers a report: { base:, head:, risen:, fallen:, sha:, trunk: }.
    def call
      raise Error, "shipshape: #{root} is not a git repository." unless git.repository?

      sha = git.merge_base(trunk_name)
      head = Offences.new(directory: root).call
      base = git.at(sha) { |path| measure_base(path) }

      report(base: base, head: head, sha: sha)
    end

    private

    attr_reader :root, :trunk, :git

    def trunk_name
      @trunk_name ||= trunk || git.default_trunk
    end

    # The head tree's config is copied in before measuring, so both runs are judged by the
    # same rules. Only the root config is copied: a config that inherits from a file
    # elsewhere in the repository gets that file from the BASE commit, which is a stated
    # limit rather than a silent one.
    def measure_base(path)
      config = File.join(root, CONFIG)
      FileUtils.cp(config, File.join(path, CONFIG)) if File.file?(config)

      Offences.new(directory: path).call
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
