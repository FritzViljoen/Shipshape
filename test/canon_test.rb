# frozen_string_literal: true

require "test_helper"

# The law and the cop are two halves of one fact, and this is what holds them together.
#
# `one-mechanism-guards-everything` says the cop list is the whole enforcement surface, so
# it has to be true in both directions: no law promising a guard that is not there, and no
# cop enforcing something no law wrote down. Either orphan makes the list a bad answer to
# "what does this repo enforce", which is the only question it exists to answer.
#
# Watched to fail: rename a cop file without touching its law, and `test_every_law_names_a_
# cop_that_exists` reddens; add a cop with no law, and `test_every_cop_is_named_by_a_law`
# reddens; delete a cop's test file and `test_every_cop_has_a_test` reddens.
class CanonTest < Minitest::Test
  LAWS = Dir[File.expand_path("../docs/laws/*.md", __dir__)].reject { |path| path.end_with?("README.md") }

  # A law naming a cop nobody built must say so, in these words. The phrase is the
  # declaration — writing it is what makes the law a convention, and it cannot go stale
  # because removing it is what turns the law back into a promise the check will test.
  UNBUILT = "not built yet"

  GUARD_LINE = /^- \*\*Guard:\*\* (.+?)(?:\n(?!  )|\z)/m
  COP_NAME = %r{`Shipshape/(\w+)`}

  def test_every_law_names_a_cop_that_exists_or_says_it_does_not
    missing = laws.reject do |law|
      law[:cops].all? { |cop| registered?(cop) } || law[:guard].downcase.include?(UNBUILT)
    end

    assert_empty missing.map { |law| "#{law[:name]} names #{law[:cops].join(', ')}" },
                 "A law naming a cop that does not exist reads as coverage. Build the cop, " \
                 "or write \"#{UNBUILT}\" in its Guard line and call it a convention."
  end

  def test_every_cop_is_named_by_a_law
    claimed = laws.flat_map { |law| law[:cops] }.to_set

    assert_empty (registered_cops - claimed).to_a,
                 "A cop enforcing something no law wrote down is a rule with no reason " \
                 "attached. Write the law, or delete the cop."
  end

  # `a-guard-states-its-limit`: a guard nobody has watched fail is coverage-shaped.
  def test_every_cop_has_a_test
    without = registered_cops.reject { |cop| File.exist?(test_path_for(cop)) }

    assert_empty without.to_a,
                 "A cop with no test may enforce nothing at all. Every guard is proven by " \
                 "removal: delete it, watch the test go red, restore it."
  end

  def test_every_law_states_its_guards_limit
    silent = laws.reject { |law| law[:body].include?("**Guard's limit:**") }

    assert_empty silent.map { |law| law[:name] },
                 "A guard that does not say what it misses is read as covering everything."
  end

  def test_the_index_lists_every_law
    index = File.read(File.expand_path("../docs/laws/README.md", __dir__))

    assert_empty laws.map { |law| law[:name] }.reject { |name| index.include?("(#{name}.md)") }
  end

  private

  def laws
    @laws ||= LAWS.sort.map do |path|
      body = File.read(path)
      guard = body[GUARD_LINE, 1].to_s

      {
        name: File.basename(path, ".md"),
        body: body,
        guard: guard,
        cops: guard.scan(COP_NAME).flatten.uniq,
      }
    end
  end

  # Read off the registry rather than off a list here. A checked-in list of cops is a second
  # copy of a fact the registry already holds, and the copy is the one that goes stale.
  def registered_cops
    @registered_cops ||= RuboCop::Cop::Registry.global.cops
                                               .map(&:cop_name)
                                               .grep(%r{\AShipshape/})
                                               .map { |name| name.split("/").last }
                                               .to_set
  end

  def registered?(cop)
    registered_cops.include?(cop)
  end

  def test_path_for(cop)
    snake = cop.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

    File.expand_path("rubocop/cop/shipshape/#{snake}_test.rb", __dir__)
  end
end
