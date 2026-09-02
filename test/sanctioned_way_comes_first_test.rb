# frozen_string_literal: true

require "test_helper"

# A cop's `instead:` carries the sanctioned pattern, and a reader stopping early only meets it
# if it sits above the matcher. Parsed, not grepped, so quoted prose inside `MODEL` in
# `enforcement_messages_are_documentation.rb` cannot look like real code.
# Watched to fail: moved `no_test_factories.rb`'s `CALLED` below its `on_send`; this reddened,
# naming the file, the constant and the matcher's line.
class SanctionedWayComesFirstTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_no_cop_writes_its_example_as_a_literal_heredoc
    offenders = analyzed.select { |cop| cop[:instead].any? { |value| value.respond_to?(:heredoc?) && value.heredoc? } }

    assert_empty offenders.map { |cop| relative_path(cop[:path]) },
                 "This passes `instead: <<~RUBY` right where the message is built, which " \
                 "sits below the matcher unless the whole method moves. Pull the heredoc out " \
                 "into a named constant — `NAME = <<~RUBY` — placed before the file's first " \
                 "`def on_`, and pass `instead: NAME` (or `instead: format(NAME, ...)` for " \
                 "one built from the offending node)."
  end

  def test_every_example_constant_is_defined_before_the_matcher
    late = analyzed.filter_map { |cop| lateness(cop) }

    assert_empty late,
                 "The constant an `instead:` names is defined after this cop's matcher, so a " \
                 "reader going top-down meets the machinery before the sanctioned example. " \
                 "Move the constant's own definition above the file's first `def on_` handler."
  end

  private

  def lateness(cop)
    return nil unless cop[:matcher_line]

    late = referenced_constant_lines(cop).select { |_name, line| line > cop[:matcher_line] }
    return nil if late.empty?

    names = late.map(&:first).sort.join(", ")
    "#{relative_path(cop[:path])}: #{names} defined after its matcher (line #{cop[:matcher_line]})"
  end

  def referenced_constant_lines(cop)
    names = cop[:instead].flat_map { |value| constant_names_in(value) }.uniq

    names.filter_map do |name|
      definition = cop[:ast].each_descendant(:casgn).find { |casgn| casgn.children[1] == name }
      definition && [name, definition.first_line]
    end
  end

  def constant_names_in(node)
    found = node.const_type? ? [node] + node.each_descendant(:const).to_a : node.each_descendant(:const).to_a

    found.map { |const_node| const_node.children.last }
  end

  def analyzed
    @analyzed ||= cop_files.map { |path| analyze(path) }
  end

  def analyze(path)
    ast = RuboCop::ProcessedSource.new(File.read(path), RUBY_VERSION.to_f, path).ast
    matcher_line = ast.each_descendant(:def)
                       .select { |definition| definition.method_name.to_s.start_with?("on_") }
                       .map(&:first_line).min
    instead = ast.each_descendant(:pair).select { |pair| pair.key.sym_type? && pair.key.value == :instead }
                 .map(&:value)

    { path: path, ast: ast, matcher_line: matcher_line, instead: instead }
  end

  def cop_files
    RuboCop::Cop::Registry.global.cops
                          .map(&:name)
                          .grep(/\ARuboCop::Cop::Shipshape::/)
                          .filter_map { |name| Object.const_source_location(name)&.first }
                          .uniq
                          .sort
  end

  def relative_path(path)
    path.delete_prefix("#{ROOT}/")
  end
end
