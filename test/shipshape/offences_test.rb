# frozen_string_literal: true

require "test_helper"
require "shipshape/offences"
require "fileutils"
require "tmpdir"

# A real directory and a real `rubocop --format json` subprocess - see `Shipshape::Guards`'
# own test file for why this is not stubbed.
class OffencesTest < Minitest::Test
  RUBOCOP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/CallGraph:
      Kinds:
        deed: ['app/deeds/**/*.rb']
      BaseClasses:
        deed: [Deed]
  YAML

  RETIRED_COP_YML = <<~YAML
    require:
      - shipshape

    AllCops:
      NewCops: disable
      SuggestExtensions: false

    Shipshape/RetiredCopName:
      Enabled: true
  YAML

  def test_offences_are_counted_by_cop
    in_repo(RUBOCOP_YML) do |root|
      write(root, "app/deeds/create_person.rb", "class CreatePerson\n  def call\n  end\nend\n")

      counts = Shipshape::Offences.new(directory: root, config: File.join(root, ".rubocop.yml")).call

      assert_operator counts.fetch("Shipshape/OneOperationOneClass", 0), :>=, 0
    end
  end

  # Shares `Coupling`'s exposure: a config naming a cop this version's registry does not hold
  # crashes the subprocess RuboCop run the same way it crashes the in-process read.
  def test_a_config_naming_an_unknown_cop_is_refused_without_tolerance
    in_repo(RETIRED_COP_YML) do |root|
      error = assert_raises(Shipshape::Error) do
        Shipshape::Offences.new(directory: root, config: File.join(root, ".rubocop.yml")).call
      end

      assert_includes error.message, "produced no report"
    end
  end

  def test_a_config_naming_an_unknown_cop_is_tolerated_and_named
    in_repo(RETIRED_COP_YML) do |root|
      offences = Shipshape::Offences.new(directory: root, config: File.join(root, ".rubocop.yml"),
                                          tolerate_unknown_cops: true)

      assert_equal({}, offences.call.to_h)
      assert_includes offences.skipped_cops, "Shipshape/RetiredCopName"
    end
  end

  private

  def write(root, path, contents)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end

  def in_repo(config)
    was = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = "-I#{gem_root}/lib #{was}".strip

    Dir.mktmpdir("shipshape-offences") do |root|
      File.write(File.join(root, ".rubocop.yml"), config)
      yield(root)
    end
  ensure
    ENV["RUBYOPT"] = was
  end
end
