# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/source_text"
require "shipshape/test_mentions"
require "shipshape/typed_arguments"

module Shipshape
  # The edges of the application, and which of them nothing tests. Every procedure moves
  # internals, so a test on one moves with it; the edge is what a refactor must not change, and
  # the only place a characterisation test is worth writing first. Asked by class, not by method,
  # and that was measured: almost no spec names the action, so matching `show` against a suite
  class Edges
    include TypedArguments

    Edge = Struct.new(:file, :klass, :actions, :covered, keyword_init: true) do
      def covered?
        covered
      end
    end

    Report = Struct.new(:edges, keyword_init: true) do
      def uncovered
        edges.reject(&:covered?)
      end

      def covered
        edges.select(&:covered?)
      end

      def actions
        edges.sum { |edge| edge.actions.length }
      end

      def ready?
        uncovered.empty?
      end
    end

    CLASS = /^\s*class\s+([\w:]+)/.freeze
    DEFINITION = /^\s*def (?:self\.)?([a-z_][\w]*[?!=]?)/.freeze

    PRIVATE = /^\s*private\s*$/.freeze

    KINDS = %w[request_handling entry_point].freeze

    def initialize(root:, settings:, kinds: KINDS)
      @root = typed(root, String)
      @settings = typed(settings, Settings)
      @kinds = typed_array(kinds, String)
    end

    def call
      Report.new(edges: files.map { |file| edge_for(file) }.compact.sort_by(&:file))
    end

    private

    attr_reader :root, :settings, :kinds

    def files
      kinds.flat_map { |kind| Array(settings.kinds[kind]) }
           .flat_map { |glob| Dir.glob(File.join(root, glob)) }
           .uniq.select { |path| File.file?(path) }.sort
    end

    def edge_for(path)
      source = SourceText.read(path)
      klass = source[CLASS, 1]
      return nil if klass.nil?

      actions = actions_in(source)
      # Where an edge inherits from, not an edge: nothing arrives at them.
      return nil if actions.empty?

      Edge.new(
        file: path.sub("#{root}/", ""),
        klass: klass,
        actions: actions,
        covered: mentions.names?(klass.split("::").last),
      )
    end

    # Everything before a bare `private`, which reaches actions and `perform` alike.
    def actions_in(source)
      source.split(PRIVATE).first.to_s.scan(DEFINITION).flatten.uniq
    end

    def mentions
      @mentions ||= TestMentions.new(root: root)
    end
  end
end
