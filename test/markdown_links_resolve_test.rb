# frozen_string_literal: true

require "test_helper"

# A markdown link is a claim that something is there. Nobody clicks every link in review.
# Watched to fail: `an-authorisation-predicate.md`'s link to `../laws/no-industry-terms-in-code.md`
# (a principle, not a law) reddened this, naming the file, the line and the target.
class MarkdownLinksResolveTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  DOCUMENTS = (Dir[File.join(ROOT, "docs/**/*.md")] + Dir[File.join(ROOT, "README.md")]).sort.freeze

  LINK = /\[[^\]]*\]\(([^)]+)\)/.freeze

  def test_every_relative_link_resolves_to_a_file_that_exists
    broken = DOCUMENTS.flat_map { |path| broken_links_in(path) }

    assert_empty broken,
                 "A markdown link that resolves to nothing sends the reader who follows it " \
                 "to a page that was never written. Fix the path, or the target file — " \
                 "whichever one is wrong — so the link lands on something that exists."
  end

  private

  def broken_links_in(path)
    File.readlines(path).each_with_index.flat_map do |line, index|
      line.scan(LINK).flatten.filter_map do |target|
        next if resolvable?(path, target)

        "#{relative(path)}:#{index + 1} -> #{target}"
      end
    end
  end

  def resolvable?(path, target)
    link, _fragment = target.split("#", 2)

    return true if link.nil? || link.empty? # a pure in-file anchor names no file
    return true if link.match?(%r{\A[a-z][a-z0-9+.-]*:}i) # a URI scheme: http:, mailto:, ...

    File.exist?(File.expand_path(link, File.dirname(path)))
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end
end
