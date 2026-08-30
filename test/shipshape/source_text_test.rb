# frozen_string_literal: true

require "test_helper"
require "shipshape/source_text"
require "shipshape/kinds"
require "shipshape/mixins"

# Watched to fail: drop the `.scrub("")` and every test here reddens with
# `ArgumentError: invalid byte sequence in UTF-8`.
#
# **The one that matters is the last.** A crash on the odd file would be a nuisance; what
# actually happened is that `Kinds` and `Mixins` read *other* files to answer about the file
# being inspected, so one bad byte anywhere in a governed tree took every kind-scoped cop
# down for the whole run. The tree went unguarded and the report said "cop errored".
class SourceTextTest < Minitest::Test
  # Valid Ruby, one byte that is not valid UTF-8. `File.read` returns it happily and the
  # first regular expression to touch it raises.
  LATIN = "class Latin < Command\n  def call; \"caf\xE9\"; end\nend\n"

  def test_a_regular_expression_survives_an_invalid_byte
    in_tree("app/commands/latin.rb" => LATIN) do |root|
      text = Shipshape::SourceText.read(File.join(root, "app/commands/latin.rb"))

      assert_match(/class Latin < Command/, text)
    end
  end

  def test_plain_file_read_is_what_this_exists_to_avoid
    in_tree("app/commands/latin.rb" => LATIN) do |root|
      raw = File.read(File.join(root, "app/commands/latin.rb"))

      assert_raises(ArgumentError) { raw =~ /Command/ }
    end
  end

  def test_lines_survives_it_too
    in_tree("app/commands/latin.rb" => LATIN) do |root|
      lines = Shipshape::SourceText.lines(File.join(root, "app/commands/latin.rb"))

      assert_equal 3, lines.length
    end
  end

  # `Kinds` reads a file to find its superclass, so the bad file broke classification.
  def test_kinds_still_classifies_a_file_holding_an_invalid_byte
    in_tree("app/commands/latin.rb" => LATIN) do |root|
      assert_equal "command", kinds(root).for_path(File.join(root, "app/commands/latin.rb"))
    end
  end

  # **The blast radius.** `Mixins` reads every operation before it can judge one module, so
  # the bad file decided the answer for a module that has nothing to do with it.
  def test_one_unreadable_file_does_not_blind_the_mixin_scan_to_the_rest
    tree = {
      "app/commands/latin.rb" => LATIN,
      "app/commands/settle_invoice.rb" => "class SettleInvoice < Command\n  include Paying\nend\n",
    }

    in_tree(tree) do |root|
      assert mixins(root).mixed_into_an_operation?("Paying"),
             "a file with one bad byte hid every include in the repository"
    end
  end

  private

  def in_tree(files)
    Dir.mktmpdir("source-text") do |root|
      files.each do |relative, body|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, body.b)
      end

      yield root
    end
  end

  def settings
    Shipshape::Settings.new(kinds: { "command" => ["app/commands/**/*.rb"] },
                            matrix: { "command" => [] },
                            base_classes: { "command" => ["Command"] })
  end

  def kinds(root)
    Shipshape::Kinds.new(settings: settings, base_dir: root)
  end

  def mixins(root)
    Shipshape::Mixins.new(settings: settings, base_dir: root, operation_kinds: ["command"])
  end
end
