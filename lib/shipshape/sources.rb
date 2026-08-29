# frozen_string_literal: true

require "rubocop"
require "shipshape/typed_arguments"

module Shipshape
  # Every Ruby file under a set of roots, parsed once.
  #
  # The report reads a repository it knows nothing about — no shipshape configuration, no
  # base classes, no agreed layout — because the first thing anybody wants is a number, and
  # asking them to configure a tool before it will tell them anything is how the tool goes
  # unused.
  class Sources
    include TypedArguments

    Source = Struct.new(:path, :relative, :ast, keyword_init: true)

    def initialize(root:, roots: ["app", "lib"])
      @root = typed(root, String)
      @roots = typed_array(roots, String)
    end

    def call
      paths.map { |path| parse(path) }.compact
    end

    # Files under a subdirectory of `app/`, by directory name — `app/models/**` becomes
    # "models". How a Rails application is laid out is the one thing that can be assumed.
    def by_directory
      call.group_by { |source| source.relative.split("/")[1] }
    end

    private

    attr_reader :root, :roots

    def paths
      roots.flat_map { |tree| Dir.glob(File.join(root, tree, "**", "*.rb")) }.sort
    end

    # A file that does not parse is skipped and does not stop the run. A legacy repository
    # is entitled to hold a file written for an older Ruby, and refusing to report anything
    # because of one is worse than reporting everything else.
    def parse(path)
      source = RuboCop::ProcessedSource.new(File.read(path), RUBY_VERSION.to_f, path)
      return nil if source.ast.nil?

      Source.new(path: path, relative: relative(path), ast: source.ast)
    # rubocop:disable Shipshape/NoEmptyRescue
    # A swallow, and a deliberate one, for the reason stated above this method: a repository
    # is entitled to hold a file this parser cannot read, and refusing to report anything
    # because of one is worse than reporting everything else.
    rescue StandardError
      nil
    end
    # rubocop:enable Shipshape/NoEmptyRescue

    def relative(path)
      path.sub("#{File.expand_path(root)}/", "").sub("#{root}/", "")
    end
  end
end
