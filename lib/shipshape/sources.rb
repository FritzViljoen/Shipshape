# frozen_string_literal: true

require "shipshape/source_text"
require "rubocop"
require "shipshape/typed_arguments"

module Shipshape
  # Every Ruby file under a set of roots, parsed once.
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

    def by_directory
      call.group_by { |source| source.relative.split("/")[1] }
    end

    private

    attr_reader :root, :roots

    def paths
      roots.flat_map { |tree| Dir.glob(File.join(root, tree, "**", "*.rb")) }.sort
    end

    # An unparseable file is skipped: a legacy repository is entitled to hold one, and refusing
    # to report anything because of it is worse than reporting everything else.
    def parse(path)
      source = RuboCop::ProcessedSource.new(SourceText.read(path), RUBY_VERSION.to_f, path)
      return nil if source.ast.nil?

      Source.new(path: path, relative: relative(path), ast: source.ast)
    # rubocop:disable Shipshape/NoEmptyRescue
    rescue StandardError
      nil
    end
    # rubocop:enable Shipshape/NoEmptyRescue

    def relative(path)
      path.sub("#{File.expand_path(root)}/", "").sub("#{root}/", "")
    end
  end
end
