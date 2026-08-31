# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "fileutils"
require "tmpdir"
require "yaml"
require "minitest/autorun"
require "rubocop"
require "shipshape"

# Runs one cop over one source string and hands back its offences.
module CopRunner
  # `other_cops` carries configuration a cop reads from a sibling — the layout is declared
  # once, on Shipshape/CallGraph, so a cop that needs it reads it from there.
  # `files` is either a list of paths, written empty, or a Hash of path => source. Write
  # real bodies whenever the kind is decided by the superclass rather than by the path —
  # an empty file has no superclass, so it would quietly test the fallback instead.
  def offences(source, cop_class:, cop_config: {}, path:, files: [], other_cops: {})
    Dir.mktmpdir("shipshape") do |root|
      write_tree(root, files)
      inspected = File.join(root, path)
      touch(inspected)
      File.write(inspected, source)

      investigate(cop_class, cop_config, root, source, inspected, other_cops)
    end
  end

  private

  def investigate(cop_class, cop_config, root, source, inspected, other_cops = {})
    config = RuboCop::Config.new(
      other_cops.merge(cop_class.cop_name => { "Enabled" => true }.merge(cop_config)),
      File.join(root, ".rubocop.yml"),
    )
    cop = cop_class.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, inspected)

    RuboCop::Cop::Commissioner
      .new([cop], [], raise_error: true)
      .investigate(processed)
      .offenses
  end

  def write_tree(root, files)
    return files.each { |file| touch(File.join(root, file)) } if files.is_a?(Array)

    files.each do |file, contents|
      target = File.join(root, file)
      touch(target)
      File.write(target, contents)
    end
  end

  def touch(path)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.touch(path)
  end
end
