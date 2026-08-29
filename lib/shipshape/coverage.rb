# frozen_string_literal: true

require "shipshape/kinds"
require "shipshape/settings"
require "shipshape/typed_arguments"

module Shipshape
  # **How much of this repository the guards can actually see.**
  #
  # A file that resolves to no kind is skipped by every kind-scoped cop — silently, and
  # indistinguishably from a file they approved of. So a clean run means nothing until you
  # know what fraction of the tree was inspected at all.
  #
  # This is not a hypothetical failure. Run over six public Rails codebases with the default
  # layout, the governed fraction was 39%, 45%, 48%, 62%, 73%, 90% — and 0% for an engine
  # monorepo, where every path is `core/app/models/…` rather than `app/models/…`. That last
  # one reported nineteen offences and looked healthy.
  #
  # `shipshape canaries` proves a cop can fire. This proves the cops can reach your code.
  # They are different questions and both have to be asked.
  class Coverage
    include TypedArguments

    Result = Struct.new(:total, :by_kind, :ungoverned, keyword_init: true) do
      def governed
        total - ungoverned.length
      end

      def percentage
        return 0 if total.zero?

        (governed * 100.0 / total).round
      end
    end

    def initialize(config:, root: Dir.pwd, globs: nil)
      @config = config
      @root = typed(root, String)
      @globs = globs
    end

    def call
      by_kind = Hash.new(0)
      ungoverned = []

      files.each do |path|
        kind = kinds.for_path(path)
        kind ? by_kind[kind] += 1 : ungoverned << relative(path)
      end

      Result.new(total: files.length, by_kind: by_kind.sort_by { |_, n| -n }.to_h, ungoverned: ungoverned)
    end

    private

    attr_reader :config, :root, :globs

    # **Every Ruby file in the repository is the denominator**, not just the trees the
    # layout already names. Measuring only the declared trees answers "is what I declared
    # declared", which is flattering and useless — an engine monorepo keeping everything at
    # `core/app/models` would report 100% while nothing was inspected.
    IGNORED = %w[
      vendor node_modules tmp log .git .bundle coverage public storage
      test spec features bin script node_modules
    ].freeze

    def files
      @files ||= begin
        found = Array(globs || "**/*.rb").flat_map { |pattern| Dir.glob(File.join(root, pattern)) }

        found.reject { |path| ignored?(relative(path)) }.uniq.sort
      end
    end

    def ignored?(relative)
      relative.split("/").any? { |segment| IGNORED.include?(segment) } ||
        relative.start_with?("db/schema", "db/seeds", "config/")
    end

    def settings
      @settings ||= Settings.layout(config)
    end

    def kinds
      @kinds ||= Kinds.new(settings: settings, base_dir: root)
    end

    def relative(path)
      path.sub(%r{\A#{Regexp.escape(root)}/}, "")
    end
  end
end
