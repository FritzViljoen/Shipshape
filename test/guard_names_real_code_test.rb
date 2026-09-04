# frozen_string_literal: true

require "test_helper"

# One mechanisable slice of `a-guard-states-its-limit`'s open question: does a Guard
# paragraph's claim still match its cop? Watched to fail: renamed `SPAN_MESSAGE` in
# `a-test-inherits-what-it-needs.md`'s prose only, leaving the cop untouched — reddened,
# naming the law, the cop and the stale token. Restored.
class GuardNamesRealCodeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  NON_RULE_DOCUMENTS = %w[README.md CLAUDE.md].freeze

  LAWS = Dir[File.join(ROOT, "docs/laws/*.md")]
         .reject { |path| NON_RULE_DOCUMENTS.include?(File.basename(path)) }.sort.freeze

  SECTION = /^- \*\*(?:Guard|Guard's limit):\*\*(.*?)(?=^- \*\*|\z)/m
  COP_NAME = %r{`Shipshape/(\w+)`}
  CONSTANT = /`([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)`/

  def test_a_guard_names_a_constant_the_cop_actually_declares
    problems = []

    LAWS.each do |law|
      body = File.read(law)
      current_cop = nil

      body.scan(SECTION) do |text|
        text = text.first
        named = COP_NAME.match(text)
        current_cop = named[1] if named
        next unless current_cop

        constants = text.scan(CONSTANT).flatten.uniq
        next if constants.empty?

        source = cop_source(current_cop)
        missing = source.nil? ? constants : constants.reject { |name| source.include?(name) }
        next if missing.empty?

        problems << "#{File.basename(law)} (#{current_cop}): #{missing.join(', ')}"
      end
    end

    assert_empty problems,
                 "A Guard paragraph backticks a Ruby constant its cop's source does not " \
                 "contain — the constant was renamed (or removed) and the prose was not, " \
                 "or the paragraph describes a mechanism the cop never had. Scoped to " \
                 "SCREAMING_SNAKE_CASE names on purpose: a lowercase method or CamelCase " \
                 "class collides with ordinary English (`install`, `value`, `workflow`) and " \
                 "produced false positives across half the canon's own prose; a two-or-more-" \
                 "word ALL-CAPS token never does, which is what makes this check exemption-" \
                 "free. It is substring search, not resolution — a constant the cop no " \
                 "longer *uses* but still mentions somewhere else would still pass, and it " \
                 "says nothing about whether the paragraph's claim about what the constant " \
                 "*does* is still true. A bare English claim like the original 'a declared " \
                 "allowlist' (never backticked as a constant) is invisible to it either way."
  end

  private

  def cop_source(cop_name)
    path = File.join(ROOT, "lib/rubocop/cop/shipshape/#{snake(cop_name)}.rb")
    File.exist?(path) ? File.read(path) : nil
  end

  def snake(cop_name)
    cop_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  end
end
