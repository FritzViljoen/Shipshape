# frozen_string_literal: true

require "test_helper"
require "open3"

# Shells to the real exe/shipshape: the defect is in the CLI's own wording.
class InstallCliTest < Minitest::Test
  EXE = File.expand_path("../../exe/shipshape", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  def run_install(dir, *flags)
    Open3.capture3(RbConfig.ruby, "-I", LIB, EXE, "install", *flags, chdir: dir)
  end

  def test_a_flag_change_is_named_as_the_cause_not_the_gem
    Dir.mktmpdir("shipshape-cli") do |dir|
      run_install(dir, "--auth")
      out, = run_install(dir)

      assert_includes out, "auth: false", "the flags this run used should be printed"
      refute_includes out, "gem ships now", "the CLI cannot know the template moved on"
      assert_includes out, "not a template that moved on"
    end
  end
end
