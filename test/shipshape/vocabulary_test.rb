# frozen_string_literal: true

require "test_helper"
require "erb"
require "shipshape/install"
require "shipshape/rules"

# Watched to fail: add a `def` to any template `Install::FILES` names, and this reddens,
# naming it, until Rules::VOCABULARY_DESCRIPTIONS or VOCABULARY_EXCLUSIONS says why.
class VocabularyTest < Minitest::Test
  DEF_PATTERN = /^\s*def\s+(?:self\.)?([a-zA-Z_][a-zA-Z0-9_]*[?!]?)/.freeze

  def test_every_method_the_templates_define_is_named_or_excused
    classified = Shipshape::Rules::VOCABULARY_DESCRIPTIONS.keys + Shipshape::Rules::VOCABULARY_EXCLUSIONS.keys
    unclassified = template_method_names - classified

    assert_empty unclassified,
      "#{unclassified.join(', ')} is defined by an installed template with no glossary " \
      "description and no exclusion reason. Add one of the two to lib/shipshape/rules.rb: " \
      "a description if an application would write this name, an exclusion (with a reason) " \
      "if it never would."
  end

  def test_every_described_method_is_named_in_the_generated_rules
    Dir.mktmpdir("vocabulary-auth") do |root|
      Shipshape::Install.new(root: root, auth: true).call
      rules = generate(root: root)

      Shipshape::Rules::VOCABULARY_DESCRIPTIONS.each_key do |name|
        assert_includes rules, "`#{name}`",
          "#{name} has a glossary description that never made it into the rendered rules file"
      end
    end
  end

  # The asymmetry that started this file: only `command` and `query` define `test_call`.
  def test_call_test_is_named_only_for_the_kinds_that_define_it
    Dir.mktmpdir("vocabulary-test-call") do |root|
      Shipshape::Install.new(root: root, auth: true).call
      rules = generate(root: root)
      line = rules.lines.find { |candidate| candidate.include?("`test_call`") }

      refute_nil line, "test_call has a description but no longer renders at all"
      assert_includes line, "command", "test_call is defined on Command; the line should say so"
      assert_includes line, "query", "test_call is defined on Query; the line should say so"
      refute_includes line, "io_command",
        "IoCommand has no test_call — asserting an actor and skipping the permission check " \
        "would be a silent behaviour change on a door that opens a real transaction"
      refute_includes line, "legacy_command", "LegacyCommand has no test_call either"
    end
  end

  def test_test_call_disappears_entirely_where_auth_is_not_installed
    rules = generate(root: Dir.mktmpdir("vocabulary-no-auth"))

    refute_includes rules, "`test_call`",
      "test_call only exists inside the `if auth` branch of its templates; with no " \
      "app/shipshape/permission.rb the method is not defined anywhere, so the glossary " \
      "must not claim it either"
  end

  private

  def generate(root:)
    Shipshape::Rules.new(config: RuboCop::ConfigStore.new.for_pwd, root: root).call
  end

  def template_method_names
    Shipshape::Install::FILES.flat_map { |name| method_names_in(name) }.uniq
  end

  def method_names_in(name)
    path = File.join(Shipshape::Install::TEMPLATES, "#{name}.rb.tt")
    auth = true
    source = ERB.new(File.read(path), trim_mode: "-").result(binding)

    source.scan(DEF_PATTERN).flatten
  end
end
