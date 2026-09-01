# frozen_string_literal: true

require "test_helper"

# One shape, so an agent opening any of the 35 finds the target before the diagnosis and the
# limits before believing the result. `What you are aiming at` was in 6 of 35 before this.
# Watched to fail: rename a section, unverify a step, or write `rule 4` into a law.
class DocumentsHaveOneShapeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  PROCEDURES = Dir[File.join(ROOT, "docs/decomposing/*.md")]
               .reject { |path| File.basename(path) == "README.md" }.sort.freeze

  LAWS = Dir[File.join(ROOT, "docs/laws/*.md")]
         .reject { |path| File.basename(path) == "README.md" }.sort.freeze

  SECTIONS = {
    "the opening" => "A procedure, meant to be followed by an agent one step at a time",
    "**What you are aiming at:**" => "**What you are aiming at:**",
    "## What this leaves you" => "## What this leaves you",
    "## What none of this proves" => "## What none of this proves",
  }.freeze

  def test_every_procedure_carries_every_section
    SECTIONS.each do |name, marker|
      missing = PROCEDURES.reject { |path| File.read(path).include?(marker) }

      assert_empty relative(missing),
                   "#{name} is what an agent looks for in a known place. A procedure without " \
                   "it is one they have to read whole to find out whether it applies."
    end
  end

  def test_every_step_ends_in_something_to_run
    bare = PROCEDURES.flat_map do |path|
      steps(File.read(path)).reject { |body| body.match?(/```sh|```bash|\*\*Check:\*\*/) }
             .map { |body| "#{File.basename(path)}: #{body.lines.first.strip}" }
    end

    assert_empty bare, "Every step ends with something to run — that is what the opening promises."
  end

  # `step 0` is an identity, not an address — the steps are in the file the reader has.
  def test_a_document_cites_no_section_by_number
    numbered = (PROCEDURES + LAWS).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{File.basename(path)}:#{index + 1}" if line.match?(/§\d|\brule \d|\bsection \d/i)
      end
    end

    assert_empty numbered,
                 "A number is an address, and the reader has to go and fetch the meaning. Say " \
                 "the rule and name it."
  end

  def test_every_code_fence_names_its_language
    bare = (PROCEDURES + LAWS).flat_map do |path|
      inside = false
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.start_with?("```")

        was = inside
        inside = !inside
        "#{File.basename(path)}:#{index + 1}" if !was && line.strip == "```"
      end
    end

    assert_empty bare, "An unlabelled fence renders unhighlighted and reads as prose."
  end

  private

  def steps(source)
    source.split(/^(?=## \d+\.)/).select { |part| part.start_with?("## ") }
  end

  def relative(paths)
    paths.map { |path| path.delete_prefix("#{ROOT}/") }
  end
end
