# frozen_string_literal: true

require "test_helper"

# Watched to fail: change `kind_of_inspected_file` back to a plain `||=` and
# `test_one_cop_instance_judges_each_file_on_its_own_path` reddens — the write is judged a record
# and reports an offence it does not have. **RuboCop builds a cop per file today, so nothing here
# is visible through the binary.** That is exactly why it is worth a test: the correctness of every
class ReadsKindsTest < Minitest::Test
  include CopRunner

  CONFIG = <<~YAML
    inherit_from:
      - CONFIG_PATH
    AllCops:
      NewCops: disable
      SuggestExtensions: false
    Shipshape/CallGraph:
      Kinds:
        write: ['app/writes/**/*.rb']
      BaseClasses:
        write: ['Write']
      Matrix:
        write: []
  YAML

  RECORD = "class Thing < ApplicationRecord\n  def total\n    1\n  end\nend\n"
  WRITE = "class Settle < Write\n  def call\n    1\n  end\nend\n"

  def test_one_cop_instance_judges_each_file_on_its_own_path
    in_tree do |root, config|
      cop = RuboCop::Cop::Shipshape::PersistenceHoldsNoBehaviour.new(config)

      record = investigate(cop, File.join(root, "app/models/thing.rb"))
      write = investigate(cop, File.join(root, "app/writes/settle.rb"))

      assert_equal 1, record, "a record holding a method is the offence this cop exists for"
      assert_equal 0, write, "the write was judged by the kind of the file before it"
    end
  end

  def test_the_order_does_not_matter
    in_tree do |root, config|
      cop = RuboCop::Cop::Shipshape::PersistenceHoldsNoBehaviour.new(config)

      write = investigate(cop, File.join(root, "app/writes/settle.rb"))
      record = investigate(cop, File.join(root, "app/models/thing.rb"))

      assert_equal 0, write
      assert_equal 1, record,
        "The reverse order too: nil is falsy, so a plain `||=` never memoised an unclassified file and this direction passed either way. It is here so the pair reads as one claim."
    end
  end

  private

  def investigate(cop, path)
    source = RuboCop::ProcessedSource.new(File.read(path), RUBY_VERSION.to_f, path)

    RuboCop::Cop::Commissioner.new([cop], [], raise_error: true).investigate(source).offenses.length
  end

  def in_tree
    Dir.mktmpdir("reads-kinds") do |root|
      write(root, "app/models/thing.rb", RECORD)
      write(root, "app/writes/settle.rb", WRITE)
      write(root, ".rubocop.yml",
            CONFIG.sub("CONFIG_PATH", File.expand_path("../../../../config/default.yml", __dir__)))

      store = RuboCop::ConfigStore.new
      store.options_config = File.join(root, ".rubocop.yml")

      yield root, store.for(File.join(root, "app/models/thing.rb"))
    end
  end

  def write(root, relative, body)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end
end
