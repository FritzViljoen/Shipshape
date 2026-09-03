# frozen_string_literal: true

require "shipshape/git"
require "shipshape/typed_arguments"

module Shipshape
  # A path's name at `ref`, resolved through however many renames got it there. Shares the
  # algorithm `CoChange` needs (PR #28, not landed) rather than a second copy of it.
  class RenamedPaths
    include TypedArguments

    RENAME = /\AR/.freeze

    def initialize(root:, ref: "HEAD")
      @root = typed(root, String)
      @ref = typed(ref, String)
      @git = Git.new(root: root)
    end

    # old path => its name at `ref`. A path never renamed is absent — fetch it with a default.
    def call
      forward = {}

      git.name_status_log(ref: ref).each_line(chomp: true) do |line|
        next if line == "COMMIT" || line.empty?

        record(forward, line)
      end

      forward
    end

    private

    attr_reader :root, :ref, :git

    def record(forward, line)
      status, *paths = line.split("\t")
      return unless status.match?(RENAME)

      old, new = paths
      forward[old] = forward.fetch(new, new)
    end
  end
end
