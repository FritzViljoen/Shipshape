# frozen_string_literal: true

require "test_helper"
require "yaml"

# The kind vocabulary is declared once, on Shipshape/CallGraph.Kinds; every other `...Kinds`
# list is a use of it, loaded as data so a value under the wrong mapping reads as RuboCop reads it.
# Watched to fail: reddened, unmodified, on the real duplicate `view_component` already in
# Shipshape/NoTypeInterrogation's `Kinds`; reddened again on a renamed `viewcomponent`.
class ConfigKindsAreSoundTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_no_kinds_list_repeats_an_entry
    dupes = kind_lists.filter_map do |path, list|
      repeated = list.tally.select { |_, count| count > 1 }.keys
      "#{path}: #{repeated.join(', ')}" unless repeated.empty?
    end

    assert_empty dupes,
                 "The same kind is named twice in one list. RuboCop's `Include`/`Kinds` " \
                 "matching does not need the repeat, and a reader takes it as two different " \
                 "kinds skimmed too fast to notice they read the same. Delete the second one."
  end

  def test_no_kinds_list_names_an_undeclared_kind
    unknown = kind_lists.filter_map do |path, list|
      bad = list.reject { |kind| declared_kinds.include?(kind) }
      "#{path}: #{bad.join(', ')}" unless bad.empty?
    end

    assert_empty unknown,
                 "This name is not one of the kinds Shipshape/CallGraph.Kinds declares, so no " \
                 "file will ever be classified into it and the cop it scopes silently covers " \
                 "nothing for that entry. Spell the kind the way CallGraph declares it, or add " \
                 "it there first if it is genuinely new."
  end

  private

  def declared_kinds
    @declared_kinds ||= config.fetch("Shipshape/CallGraph").fetch("Kinds").keys
  end

  def kind_lists
    @kind_lists ||= collect(config, [])
  end

  def collect(node, path)
    return [] unless node.is_a?(Hash)

    node.flat_map do |key, value|
      here = path + [key]

      if key.to_s.end_with?("Kinds") && value.is_a?(Array)
        [[here.join("."), value]]
      else
        collect(value, here)
      end
    end
  end

  def config
    @config ||= YAML.load_file(File.join(ROOT, "config/default.yml"))
  end
end
