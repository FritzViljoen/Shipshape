# frozen_string_literal: true

require "test_helper"
require "yaml"

# A number in prose beside a countable set is a second copy of that count. Two instances of
# it, checked against the set each one names: a law's writing-operation count against
# `AUDITED_DOORS`, and a `config/default.yml` comment's per-cop kind counts against those
# cops' own `Kinds:` lists. See each assertion for what a derived number cannot catch.
class CountClaimsMatchCodeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  NON_RULE_DOCUMENTS = %w[README.md CLAUDE.md].freeze

  LAWS = Dir[File.join(ROOT, "docs/laws/*.md")]
         .reject { |path| NON_RULE_DOCUMENTS.include?(File.basename(path)) }.sort.freeze

  NUMBER_WORDS = %w[one two three four five six seven eight nine ten].freeze

  def test_writing_operation_counts_match_generated_base_classes_test
    truth = audited_doors_count
    mismatches = LAWS.filter_map do |law|
      body = File.read(law)
      claims = body.scan(/\b(#{NUMBER_WORDS.join('|')})\b\s+writing operations?\b/i).flatten
      claims += body.scan(/\beach of the (#{NUMBER_WORDS.join('|')})\b/i).flatten if body.include?("writing operation")
      claims = claims.map { |word| NUMBER_WORDS.index(word.downcase) + 1 }.uniq

      next if claims.empty?

      "#{File.basename(law)}: claims #{claims.inspect}, AUDITED_DOORS has #{truth}" if claims != [truth]
    end

    assert_empty mismatches,
                 "A law's writing-operation count no longer matches AUDITED_DOORS in " \
                 "generated_base_classes_test.rb — the set changed and the prose did not. " \
                 "Watched to fail: changed 'three' to 'four' in one law with no code " \
                 "change, and separately shrank AUDITED_DOORS by one with no doc change; " \
                 "both reddened, naming the law and the mismatched pair. Only catches a " \
                 "count next to the literal phrase 'writing operation(s)', or an 'each of " \
                 "the N' in a document that also says it — a stale count spelled any other " \
                 "way is invisible to it."
  end

  def test_kind_count_comments_match_the_cops_they_describe
    lines = File.readlines(default_config_path)
    config = YAML.load_file(default_config_path)
    trigger = /\b(#{NUMBER_WORDS.join('|')})\s+cops?\s+below\b/i

    mismatches = []

    lines.each_with_index do |line, index|
      next unless line.lstrip.start_with?("#") && line.match?(trigger)

      claimed = NUMBER_WORDS.index(trigger.match(line)[1].downcase) + 1
      block_end = index
      block_end += 1 while block_end < lines.length && lines[block_end].lstrip.start_with?("#")
      block_text = lines[index...block_end].join

      counts = block_text.scan(/(\d+(?:\s*,\s*\d+)*(?:\s+and\s+\d+)?)\s+kinds\b/i)
                          .flatten.flat_map { |group| group.scan(/\d+/) }.map(&:to_i)

      if counts.length != claimed
        mismatches << "line #{index + 1}: claims #{claimed} cops but names #{counts.length} kind-counts"
        next
      end

      keys = []
      cursor = block_end
      while cursor < lines.length && keys.length < claimed
        keys << Regexp.last_match(1) if lines[cursor] =~ /^(Shipshape\/\w+):\s*$/
        cursor += 1
      end

      keys.each_with_index do |key, position|
        actual = config.dig(key, "Kinds")&.length
        expected = counts[position]
        next if actual == expected

        mismatches << "#{key}: comment above line #{index + 1} claims #{expected} kinds, has #{actual.inspect}"
      end
    end

    assert_empty mismatches,
                 "A comment in config/default.yml claims a Kinds count for the cops below " \
                 "it that no longer matches what those cops declare. Watched to fail: " \
                 "added a fourth Kinds entry to Shipshape/NoAmbientReads with the comment " \
                 "unchanged — reddened, naming the cop, its claimed count and its actual " \
                 "count. Only pairs a claimed number with the Nth cop key after the " \
                 "comment by position: a comment that correctly counts N cops but names " \
                 "the wrong N keys — because something else was inserted between — would " \
                 "still pass."
  end

  private

  def audited_doors_count
    path = File.join(ROOT, "test/shipshape/generated_base_classes_test.rb")
    source = File.read(path)
    list = source[/AUDITED_DOORS\s*=\s*\[(.*?)\]\.freeze/m, 1]
    raise "AUDITED_DOORS not found in #{path}" unless list

    list.split(",").map(&:strip).reject(&:empty?).size
  end

  def default_config_path
    File.join(ROOT, "config/default.yml")
  end
end
