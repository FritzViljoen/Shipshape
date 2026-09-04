# frozen_string_literal: true

require "test_helper"

# The corpus cites a law, principle or procedure by its kebab-case identifier, backticked.
# Watched to fail: reddened unmodified on two names already dangling in the corpus (one in
# the-call-graph-is-declared.md, one in no_hidden_test_methods_test.rb); green once renamed.
class RuleCitationsResolveTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Four words or more: shorter is indistinguishable from a gem name like `rack-attack`.
  CITATION = /`([a-z][a-z0-9]*(?:-[a-z0-9]+){3,})`/.freeze

  def test_every_long_kebab_case_citation_resolves_to_a_law_a_principle_or_a_procedure
    known = laws.to_set.merge(principles).merge(procedures)

    dangling = tracked_files.flat_map { |path| dangling_citations_in(path, known) }

    assert_empty dangling,
                 "This name is cited like a law, a principle or a procedure, backticked and " \
                 "written out in full, but none of the three files it could be exists under " \
                 "that identifier. Rename the citation to match the real one, or write the " \
                 "document it is missing."
  end

  private

  def dangling_citations_in(path, known)
    File.readlines(path).each_with_index.flat_map do |line, index|
      line.scan(CITATION).flatten.reject { |name| known.include?(name) }
          .map { |name| "#{relative(path)}:#{index + 1} -> `#{name}`" }
    end
  end

  def laws
    Dir[File.join(ROOT, "docs/laws/*.md")]
      .map { |path| File.basename(path, ".md") }
      .reject { |name| name == "README" }
  end

  def principles
    File.read(File.join(ROOT, "docs/principles.md"))
        .scan(/^### `([a-z][a-z0-9-]*)`/).flatten
  end

  def procedures
    Dir[File.join(ROOT, "docs/decomposing/*.md")]
      .map { |path| File.basename(path, ".md") }
      .reject { |name| name == "README" }
  end

  def tracked_files
    Dir.chdir(ROOT) { `git ls-files`.split("\n") }.map { |path| File.join(ROOT, path) }
       .select { |path| File.file?(path) }
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end
end
