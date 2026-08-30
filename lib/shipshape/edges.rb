# frozen_string_literal: true

require "shipshape/settings"
require "shipshape/source_text"
require "shipshape/test_mentions"
require "shipshape/typed_arguments"

module Shipshape
  # **The edges of the application, and which of them nothing tests.**
  #
  # Every procedure in this playbook moves internals, so a test on an internal moves with it
  # and proves nothing. The edge is the one thing a refactor must not change: a request that
  # answered 302 answers 302 afterwards, whatever happened underneath. That makes the edge the
  # only place a characterisation test is worth writing before the work starts, and this is
  # the list of them.
  #
  # **The layout already declares where they are.** `request_handling` and `entry_point` are
  # kinds, so an application that told `Shipshape/CallGraph` where its controllers and jobs
  # live has already answered this and is not asked twice.
  #
  # **Asked by class, not by method**, and that was measured rather than assumed. A request
  # spec says `get "/stories"` and a controller spec says `describe StoriesController`; almost
  # none of them name the action. Matching `show` against a suite answers yes for any file
  # containing the word — the flattering answer. The class name is what a test that exercises
  # this edge actually contains.
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

      # Nothing should move until something can say it broke.
      def ready?
        uncovered.empty?
      end
    end

    CLASS = /^\s*class\s+([\w:]+)/.freeze
    DEFINITION = /^\s*def (?:self\.)?([a-z_][\w]*[?!=]?)/.freeze

    # A bare `private` ends the public surface. What follows is a helper, not an edge.
    PRIVATE = /^\s*private\s*$/.freeze

    # The kinds the outside world arrives through.
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
      # `ApplicationController` and `ApplicationJob` define no action. They are where an edge
      # inherits from, not an edge — nothing arrives at them.
      return nil if actions.empty?

      Edge.new(
        file: path.sub("#{root}/", ""),
        klass: klass,
        actions: actions,
        covered: mentions.names?(klass.split("::").last),
      )
    end

    # Everything before a bare `private`: a controller's actions, a job's `perform`. The same
    # rule reaches both without either being named here.
    def actions_in(source)
      source.split(PRIVATE).first.to_s.scan(DEFINITION).flatten.uniq
    end

    def mentions
      @mentions ||= TestMentions.new(root: root)
    end
  end
end
