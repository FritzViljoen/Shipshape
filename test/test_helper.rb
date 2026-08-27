# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "fileutils"
require "tmpdir"
require "minitest/autorun"
require "rubocop"
require "shipshape"

# Runs one cop over one source string and hands back its offences.
#
# The cop resolves kinds from the filesystem, so a test builds a real tree in a temporary
# directory rather than stubbing the lookup. Stubbing it would test the matrix and leave
# the resolution — the part that actually goes wrong — unexercised.
module CopRunner
  def offences(source, cop_class:, cop_config: {}, path:, files: [])
    Dir.mktmpdir("shipshape") do |root|
      files.each { |file| touch(File.join(root, file)) }
      inspected = File.join(root, path)
      touch(inspected)

      investigate(cop_class, cop_config, root, source, inspected)
    end
  end

  private

  def investigate(cop_class, cop_config, root, source, inspected)
    config = RuboCop::Config.new(
      { cop_class.cop_name => { "Enabled" => true }.merge(cop_config) },
      File.join(root, ".rubocop.yml"),
    )
    cop = cop_class.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, inspected)

    RuboCop::Cop::Commissioner
      .new([cop], [], raise_error: true)
      .investigate(processed)
      .offenses
  end

  def touch(path)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.touch(path)
  end
end
