# frozen_string_literal: true

require "test_helper"
require "open3"

# Shells to the real exe/shipshape: the two defects are in the CLI's own wording, which
# nothing else exercises.
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

  def test_a_new_file_no_longer_needed_is_named_stale
    Dir.mktmpdir("shipshape-cli") do |dir|
      run_install(dir)
      target = File.join(dir, "app/shipshape/write.rb")
      File.write(target, "#{File.read(target)}# mine\n")
      run_install(dir)
      FileUtils.cp("#{target}.new", target)

      out, = run_install(dir)

      assert_includes out, "STALE"
      assert_includes out, "app/shipshape/write.rb.new"
      assert_path_exists "#{target}.new", "a `.new` is reported, never deleted"
    end
  end
end
