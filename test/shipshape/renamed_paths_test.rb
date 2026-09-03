# frozen_string_literal: true

require "test_helper"
require "shipshape/renamed_paths"
require "open3"
require "fileutils"

# A real repository, real renames — `Coupling`'s canonicalisation needs this to be right for
# the exact chained-rename shape `CoChange` already proved it for on `feat/files-that-change-
# together` (PR #28): one primitive (`Git#name_status_log`), read the same way here.
class RenamedPathsTest < Minitest::Test
  def test_a_path_never_renamed_is_absent_from_the_map
    in_repo do |root|
      write(root, "steady.rb", "1")
      commit(root, "add")

      forward = Shipshape::RenamedPaths.new(root: root).call

      refute forward.key?("steady.rb")
    end
  end

  def test_a_single_rename_resolves_old_to_new
    in_repo do |root|
      write(root, "old_name.rb", "1")
      commit(root, "add")

      git!(root, "mv", "old_name.rb", "new_name.rb")
      commit(root, "rename")

      forward = Shipshape::RenamedPaths.new(root: root).call

      assert_equal "new_name.rb", forward.fetch("old_name.rb")
    end
  end

  # `CoChange`'s own proof for this exact shape: a chain resolves to the name that exists at
  # HEAD, however many hops it took to get there.
  def test_a_chain_of_renames_resolves_to_the_final_name
    in_repo do |root|
      write(root, "name_a.rb", "1")
      commit(root, "add")

      git!(root, "mv", "name_a.rb", "name_b.rb")
      commit(root, "first rename")

      git!(root, "mv", "name_b.rb", "name_c.rb")
      commit(root, "second rename")

      forward = Shipshape::RenamedPaths.new(root: root).call

      assert_equal "name_c.rb", forward.fetch("name_a.rb")
      assert_equal "name_c.rb", forward.fetch("name_b.rb")
    end
  end

  # A rename that happened after `ref` is not this lookup's business — `ref` names the tip.
  def test_only_renames_reachable_from_ref_are_seen
    in_repo do |root|
      write(root, "old_name.rb", "1")
      commit(root, "add")
      sha = capture(root, "rev-parse", "HEAD").strip

      git!(root, "mv", "old_name.rb", "new_name.rb")
      commit(root, "rename")

      forward = Shipshape::RenamedPaths.new(root: root, ref: sha).call

      refute forward.key?("old_name.rb")
    end
  end

  private

  def in_repo
    Dir.mktmpdir("shipshape-renamed-paths") do |root|
      git!(root, "init", "--quiet", "-b", "trunk")
      git!(root, "config", "user.email", "test@example.com")
      git!(root, "config", "user.name", "test")

      yield(root)
    end
  end

  def write(root, path, contents)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  def commit(root, message)
    git!(root, "add", "-A")
    git!(root, "commit", "--quiet", "-m", message)
  end

  def git!(root, *arguments)
    _, err, status = Open3.capture3("git", "-C", root, *arguments)
    raise "git #{arguments.first}: #{err}" unless status.success?
  end

  def capture(root, *arguments)
    out, = Open3.capture3("git", "-C", root, *arguments)
    out
  end
end
