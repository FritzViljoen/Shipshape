# frozen_string_literal: true

require "test_helper"
require "open3"
require "fileutils"

# Shells to the real exe/shipshape: proves the flags reach `Shipshape::CoChange`, which its
# own test suite already covers in depth.
class CoChangeCliTest < Minitest::Test
  EXE = File.expand_path("../../exe/shipshape", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  def test_reports_a_pair_from_a_real_repository
    Dir.mktmpdir("shipshape-cochange-cli") do |dir|
      git!(dir, "init", "--quiet", "-b", "trunk")
      git!(dir, "config", "user.email", "test@example.com")
      git!(dir, "config", "user.name", "test")
      File.write(File.join(dir, "a.rb"), "a")
      File.write(File.join(dir, "b.rb"), "b")
      git!(dir, "add", "-A")
      git!(dir, "commit", "--quiet", "-m", "together")

      out, _err, status = Open3.capture3(RbConfig.ruby, "-I", LIB, EXE, "cochange", chdir: dir)

      assert status.success?
      assert_includes out, "a.rb"
      assert_includes out, "b.rb"
      assert_includes out, "1 commit(s) scanned"
      assert_includes out, "CHURN"
    end
  end

  def test_json_flag_emits_parseable_rows
    Dir.mktmpdir("shipshape-cochange-cli") do |dir|
      git!(dir, "init", "--quiet", "-b", "trunk")
      git!(dir, "config", "user.email", "test@example.com")
      git!(dir, "config", "user.name", "test")
      File.write(File.join(dir, "a.rb"), "a")
      File.write(File.join(dir, "b.rb"), "b")
      git!(dir, "add", "-A")
      git!(dir, "commit", "--quiet", "-m", "together")

      out, = Open3.capture3(RbConfig.ruby, "-I", LIB, EXE, "cochange", "--json", chdir: dir)
      rows = JSON.parse(out)

      assert_equal 1, rows.fetch("pairs").length
      assert_equal 1, rows.fetch("pairs").first.fetch("shared")
      assert_equal 2, rows.fetch("churn").length
    end
  end

  private

  def git!(root, *arguments)
    _, err, status = Open3.capture3("git", "-C", root, *arguments)
    raise "git #{arguments.first}: #{err}" unless status.success?
  end
end
