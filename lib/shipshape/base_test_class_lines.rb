# frozen_string_literal: true

require "json"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Every file `Shipshape/BaseTestClassGrowth` watches, and its qualifying class or module
  # body's size in lines — not the whole file, and not only files currently holding an offence.
  #
  # A subprocess, like `Offences` and `Guards`: RuboCop resolves a cop's `Include`/`Exclude`
  # relative to the process's directory when the gem's defaults loaded, not to one handed to
  # it later — so measuring two trees means two processes.
  class BaseTestClassLines
    include TypedArguments

    SCRIPT = <<~'RUBY'
      require "json"
      require "shipshape"
      require "rubocop/cop/shipshape/base_test_class_growth"
      require "shipshape/canaries"

      config_path = ARGV.shift
      store = RuboCop::ConfigStore.new
      store.options_config = config_path unless config_path.empty?
      config = store.for_dir(Dir.pwd)
      cop = RuboCop::Cop::Shipshape::BaseTestClassGrowth.new(config)
      growth = RuboCop::Cop::Shipshape::BaseTestClassGrowth

      def span_of(node, growth)
        return node.loc.line..node.loc.last_line if node.module_type?
        return nil unless growth.qualifying_superclass?(node.parent_class&.source)

        node.loc.line..node.loc.last_line
      end

      # Nested spans - a module wrapping the class it declares - would otherwise count the
      # same lines twice; overlapping spans merge into one before they are summed.
      def merged_size(spans)
        spans.sort_by(&:first).each_with_object([]) do |span, merged|
          last = merged.last

          if last && span.first <= last.last
            merged[-1] = last.first..[last.last, span.last].max
          else
            merged << span
          end
        end.sum(&:size)
      end

      # A canary is a deliberate violation; replanting it under a new rule is not this
      # application's base class holding more, so the canary tree is not this ratchet's business.
      root = Dir.pwd
      canaries = File.join(root, Shipshape::Canaries::DIRECTORY)
      candidates = RuboCop::TargetFinder.new(store, {}).target_files_in_dir(root)
      lines = candidates.each_with_object({}) do |path, rows|
        next if path.start_with?("#{canaries}/")
        next unless cop.relevant_file?(path)

        source = RuboCop::AST::ProcessedSource.from_file(path, RUBY_VERSION.to_f)
        relative = path.delete_prefix("#{root}/")

        next rows[relative] = 0 unless source.valid_syntax? && source.ast

        spans = source.ast.each_node(:class, :module).filter_map { |node| span_of(node, growth) }
        rows[relative] = merged_size(spans)
      end

      puts JSON.dump(lines)
    RUBY

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    def call
      JSON.parse(json)
    end

    private

    attr_reader :directory, :config

    def json
      out, err, status = Open3.capture3(RbConfig.ruby, "-e", SCRIPT, "--", config.to_s, chdir: directory)
      return out if status.success? && out.start_with?("{")

      raise Error, "shipshape: could not measure base test class lines in #{directory}: #{err.strip}"
    end
  end
end
