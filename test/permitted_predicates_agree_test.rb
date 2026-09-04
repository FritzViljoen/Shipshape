# frozen_string_literal: true

require "test_helper"
require "set"

# Two cops once stated one rule with different lists: no_decisions_in_request_handling.rb's
# `PERMITTED` constant named `success?` and `present?`; presence_is_not_redefined.rb's own
# message dropped `success?` and no check noticed. See the assertion message for what this
# checks and what it cannot.
class PermittedPredicatesAgreeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  PERMITTED_COP = File.join(ROOT, "lib/rubocop/cop/shipshape/no_decisions_in_request_handling.rb")

  ANCHOR = /and nothing else/
  TOKEN = /`(\w+\?)`/

  def test_every_and_nothing_else_predicate_list_matches_permitted
    truth = permitted_set
    mismatches = []

    Dir[File.join(ROOT, "lib/rubocop/cop/shipshape/*.rb")].sort.each do |path|
      sentences_with_tokens(strings_in(path)).each do |sentence, tokens|
        next if tokens == truth

        mismatches << "#{relative(path)}: #{tokens.to_a.sort.inspect} in \"#{sentence.strip}\""
      end
    end

    sentences_with_tokens(default_yml_descriptions).each do |sentence, tokens|
      next if tokens == truth

      mismatches << "config/default.yml: #{tokens.to_a.sort.inspect} in \"#{sentence.strip}\""
    end

    assert_empty mismatches,
                 "A predicate list closed with \"and nothing else\" no longer matches " \
                 "Shipshape/NoDecisionsInRequestHandling's own PERMITTED constant " \
                 "(#{truth.to_a.sort.inspect}) — PERMITTED is the only side with real " \
                 "data, an array of symbols, parsed here by casgn rather than re-typed as " \
                 "a second list; every other side is prose. Watched to fail both ways: " \
                 "dropped success? from presence_is_not_redefined.rb's message with " \
                 "PERMITTED untouched, and separately dropped :present? from PERMITTED " \
                 "itself; each reddened, naming every site still claiming the old pair. " \
                 "Sentence-scoped and anchored on the literal phrase 'and nothing else' " \
                 "next to a backticked `x?` token, chosen over matching by subject " \
                 "(fragile, and warned against elsewhere in this canon) because that exact " \
                 "pairing appears nowhere else in the codebase. A restatement spelled " \
                 "without that phrase, without backticks, or split across two sentences is " \
                 "invisible to it, and a new PERMITTED-shaped list would need its own " \
                 "instance of this same check."
  end

  private

  def permitted_set
    ast = RuboCop::ProcessedSource.new(File.read(PERMITTED_COP), RUBY_VERSION.to_f, PERMITTED_COP).ast
    casgn = ast.each_descendant(:casgn).find { |node| node.children[1] == :PERMITTED }
    raise "Shipshape::NoDecisionsInRequestHandling::PERMITTED not found — has it been renamed?" unless casgn

    array = casgn.children[2]
    array = array.children.first if array.respond_to?(:send_type?) && array.send_type?
    array.children.map { |sym| sym.children.first.to_s }.to_set
  end

  def strings_in(path)
    ast = RuboCop::ProcessedSource.new(File.read(path), RUBY_VERSION.to_f, path).ast
    return [] unless ast

    ast.each_descendant(:str).filter_map(&:value).uniq
  end

  def default_yml_descriptions
    yaml = File.read(File.join(ROOT, "config/default.yml"))
    yaml.scan(/Description: >-\n((?:^ {4}.*\n)+)/).map { |(text)| text.tr("\n", " ") }
  end

  def sentences_with_tokens(strings)
    strings.flat_map { |string| string.split(/(?<=[.!?])\s+/) }
           .select { |sentence| sentence.match?(ANCHOR) }
           .filter_map do |sentence|
             tokens = sentence.scan(TOKEN).flatten.to_set
             [sentence, tokens] unless tokens.empty?
           end
           .uniq
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end
end
