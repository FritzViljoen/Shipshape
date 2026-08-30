# frozen_string_literal: true

require "test_helper"
require "shipshape/install"
require "yaml"

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

  # The words a cop test carries to say its guard was watched to fail.
  REMOVAL_CLAIM = "Watched to fail"

  GUARD_LINE = /^- \*\*Guard:\*\* (.+?)(?:\n(?!  )|\z)/m
  COP_NAME = %r{`Shipshape/(\w+)`}

  # The guards that are deliberately not cops, each argued in the law that names it and
  # each shipping with this gem's own suite rather than running in a consuming build.
  # Being on this list is what makes a non-cop guard legitimate; the list cannot go stale
  # because nothing else grants that status.
  SUITE_GUARDS = ["CanonTest", "CanariesTest", "generated_base_classes_test.rb"].freeze

  # Installed files that carry no rule of their own, each with the reason. Being on this list
  # is what grants the exemption, so it cannot go stale: a file that grows a rule has to be
  # taken off it, and nothing else confers the status.


  # **Laws nobody sanctioned.** Being on this list is what makes an unratified law tolerable
  # rather than a defect, and adding to it is a visible act in a diff — which is the whole
  # mechanism. It shrinks; it does not grow without somebody noticing.
  #
  # Every one of these was written by an agent in answer to a *question* — an audit, a "is
  # this covered" — rather than a request for a new rule. The code they describe was already
  # enforced; what was unsanctioned was writing it down as law and thereby making it binding.
  UNRATIFIED = %w[
    a-query-only-reads
  ].freeze

  # Cops whose offences are not a refactor, each with the reason. Being on this list is what
  # grants the exemption; nothing else confers it, so a cop that becomes app-facing has to
  # come off it.
  PROCEDURE_WOULD_NOT_HELP = {
    "EnforcementMessagesAreDocumentation" =>
      "guards this gem's own cops, so it never fires on an application at all.",
    "OperationsReportWhatTheyDid" =>
      "an installed base class lost a line and the fix is to put it back. Nothing is moved, " \
      "so there is no decomposition to describe — same position as its sibling below.",
    "EveryDoorChecksPermission" =>
      "authorisation is a rollout rather than a decomposition: nothing is moved, a check " \
      "is added. It reports zero until `shipshape install --auth` has been run.",
  }.freeze

  ARCHITECTURE_WITHOUT_A_LAW = {
    "boolean" => "a name, so `Boolean` can be written in a type guard. It decides nothing.",
    "persistence" => "one definition of what a record is, used by the guards that have laws.",
  }.freeze

  def test_every_law_names_a_cop_that_exists_or_says_it_does_not
    missing = laws.reject do |law|
      law[:cops].all? { |cop| registered?(cop) } || law[:guard].downcase.include?(UNBUILT)
    end

    assert_empty missing.map { |law| "#{law[:name]} names #{law[:cops].join(', ')}" },
                 "A law naming a cop that does not exist reads as coverage. Build the cop, " \
                 "or write \"#{UNBUILT}\" in its Guard line and call it a convention."
  end

  # `[].all?` is true, so a law naming no cop at all used to pass this suite without
  # anybody deciding it should. A guard has to be named — a cop, a listed suite guard, or
  # the words that make it a convention.
  def test_every_law_names_some_guard
    silent = laws.reject do |law|
      law[:cops].any? ||
        law[:guard].downcase.include?(UNBUILT) ||
        SUITE_GUARDS.any? { |guard| law[:guard].include?(guard) }
    end

    assert_empty silent.map { |law| law[:name] },
                 "A law whose Guard line names nothing passes every other check here " \
                 "vacuously. Name a cop, name a suite guard, or say \"#{UNBUILT}\"."
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

  # A test file existing is not the same as a guard having been watched to fail. This holds
  # the declaration: each cop test names the removals somebody performed and what reddened.
  # Writing it is the claim — it cannot be satisfied by a file that tests nothing, and it
  # cannot go stale in the way a checked-in list of "verified cops" would, because nothing
  # else confers the status.
  def test_every_cop_test_names_the_removals_that_proved_it
    unproven = registered_cops.select do |cop|
      path = test_path_for(cop)

      File.exist?(path) && !File.read(path).include?(REMOVAL_CLAIM)
    end

    assert_empty unproven.to_a,
                 "`a-guard-states-its-limit` requires every guard to be proven by removal. " \
                 "Delete the guard, watch the test go red, restore it — then say so in a " \
                 "\"#{REMOVAL_CLAIM}\" comment naming which removal reddened which test."
  end

  def test_every_law_states_its_guards_limit
    silent = laws.reject { |law| law[:body].include?("**Guard's limit:**") }

    assert_empty silent.map { |law| law[:name] },
                 "A guard that does not say what it misses is read as covering everything."
  end

  # **The third direction.** Code here is constrained from three sides — the documentation
  # says the rule, a cop catches it after it is written, and the generated base classes make
  # it impossible to write. The first two hold each other above: no law without a cop, no cop
  # without a law. Nothing held the third, so a base class could enforce something no
  # document stated and nobody would find out.
  #
  # It had happened twice by the time this was written. "A command is exactly one
  # transaction" lived as reasoning inside another law, and the Result contract — a `TypeError`
  # raised at every door — was written down nowhere at all. Both were real rules, enforced on
  # every call, invisible to the canon.
  #
  # Named in a **Guard line**, not merely mentioned somewhere in the prose: that line is where
  # a law says what holds it, and matching the body would pass on an offhand reference.
  def test_every_installed_file_is_named_by_a_law
    guards = laws.map { |law| law[:guard] }.join("\n")

    unclaimed = installed.reject do |file|
      ARCHITECTURE_WITHOUT_A_LAW.key?(file) || guards.include?("#{file}.rb")
    end

    assert_empty unclaimed,
                 "These are installed into an application and constrain what it can do, and " \
                 "no law's Guard line names them. Write the law, name the file in its Guard " \
                 "line, or declare it on ARCHITECTURE_WITHOUT_A_LAW with the reason."
  end

  # The other direction: a law may not claim a base class that is not installed.
  def test_no_law_names_a_file_that_is_not_installed
    # A suite guard is named the same way and is not installed anywhere — it ships with the
    # gem and runs here.
    suite = SUITE_GUARDS.map { |guard| guard.sub(/\.rb\z/, "") }
    named = laws.flat_map { |law| law[:guard].scan(/`(\w+)\.rb`/).flatten }.uniq
    missing = named - installed - suite

    assert_empty missing,
                 "A law naming a generated file that nobody installs is a rule with no " \
                 "mechanism behind it."
  end

  # **The architecture and the guard have to agree about which kinds are covered.**
  #
  # A base class that includes `TypedArguments` is a class whose initializer is meant to be
  # asserted. If the cop is not scoped to that kind, the machinery ships and nothing requires
  # anybody to use it — which is what had happened to `shape`: every generated `Shape`
  # included `TypedArguments`, and a shape could still take a positional argument, a `**rest`,
  # or an unguarded keyword with nothing objecting. In the one class whose entire job is to be
  # a validated value.
  #
  # Derived from the templates and the shipped `BaseClasses` map rather than listed here, so
  # it cannot go stale: add a base class that includes the module and this asks for its kind.
  def test_every_base_class_that_types_its_arguments_is_a_kind_the_cop_covers
    covered = default_config.fetch("Shipshape/TypedArguments").fetch("Kinds")

    missing = kinds_of_templates_including("TypedArguments").reject { |kind| covered.include?(kind) }

    assert_empty missing,
                 "These kinds ship a base class that includes TypedArguments, so their " \
                 "initializers are meant to be asserted — but Shipshape/TypedArguments is " \
                 "not scoped to them, so nothing requires it."
  end

  # **A cop says a thing is wrong. A procedure says how to move it.** Without the second, an
  # agent handed 29,644 offences has an enumeration and no method — which is how a refactor
  # becomes a rewrite with extra confidence.
  #
  # Measured against seven public repositories, the procedures covered 87% of what an agent
  # actually meets, and the largest uncovered item was the commonest work of all: the call-site
  # sweep, 1,883 sites, which every other procedure depends on and none of them described.
  def test_every_cop_has_a_procedure_that_names_it
    prose = Dir[File.expand_path("../docs/decomposing/*.md", __dir__)]
            .reject { |path| path.end_with?("README.md") }
            .map { |path| File.read(path) }.join("\n")

    orphans = registered_cops.reject do |cop|
      PROCEDURE_WOULD_NOT_HELP.key?(cop) || prose.include?(cop)
    end

    assert_empty orphans.to_a,
                 "No procedure in docs/decomposing names these, so an agent meeting one is " \
                 "told the code is wrong and not how to move it. Write the procedure, name " \
                 "the cop in it, or declare it on PROCEDURE_WOULD_NOT_HELP with the reason."
  end

  def test_the_decomposing_index_lists_every_procedure
    index = File.read(File.expand_path("../docs/decomposing/README.md", __dir__))

    missing = Dir[File.expand_path("../docs/decomposing/*.md", __dir__)]
              .map { |path| File.basename(path) }
              .reject { |name| name == "README.md" || index.include?("(#{name})") }

    assert_empty missing, "A procedure nothing links to is one nobody will find."
  end

  # **A law is a rule somebody agreed to, and an agent cannot agree on their own behalf.**
  #
  # This exists because one did — repeatedly. Asked to audit the canon, an agent wrote two new
  # laws; asked whether the kinds were guarded, it wrote a third and a cop to hold it. Each was
  # defensible and none was requested, and a canon that grows by an agent's judgement is not a
  # canon anybody agreed to follow.
  #
  # The record cannot be forged in any interesting sense — an agent can type a name — but it
  # cannot be *omitted*, and it lands in a diff where a person sees it. That is the same
  # mechanism as `Watched to fail`: writing the claim is the act, and the check makes the claim
  # compulsory.
  def test_every_law_records_that_it_was_agreed
    silent = laws.reject { |law| law[:body].include?("**Agreed:**") }

    assert_empty silent.map { |law| law[:name] },
                 "A law with no **Agreed:** line is a rule that arrived without anybody " \
                 "deciding it should. Name who agreed and when, or write UNRATIFIED and add " \
                 "it to CanonTest::UNRATIFIED."
  end

  # The list is the fact: a new unratified law has to be added to it by hand, in a diff.
  def test_no_law_is_unratified_without_being_listed
    found = laws.select { |law| law[:body].include?("**Agreed:** UNRATIFIED") }.map { |law| law[:name] }

    assert_equal UNRATIFIED.sort, found.sort,
                 "An unratified law appeared, or a listed one was ratified without the list " \
                 "being updated. Either is a change somebody has to see."
  end

  def test_the_index_lists_every_law
    index = File.read(File.expand_path("../docs/laws/README.md", __dir__))

    assert_empty laws.map { |law| law[:name] }.reject { |name| index.include?("(#{name}.md)") }
  end

  private

  def default_config
    @default_config ||= YAML.load_file(File.expand_path("../config/default.yml", __dir__))
  end

  # A template's constant is its file name camelised; `BaseClasses` maps a kind to the
  # constants that stand for it. That is the join, and both halves are already declared.
  def kinds_of_templates_including(mixin)
    base_classes = default_config.fetch("Shipshape/CallGraph").fetch("BaseClasses")

    Dir[File.expand_path("../lib/shipshape/templates/*.rb.tt", __dir__)].filter_map do |path|
      next unless File.read(path).include?("include #{mixin}")

      constant = File.basename(path, ".rb.tt").split("_").map(&:capitalize).join
      base_classes.find { |_, names| names.include?(constant) }&.first
    end.uniq.sort
  end

  def installed
    Shipshape::Install::FILES + Shipshape::Install::TESTS
  end

  def laws
    @laws ||= LAWS.sort.map do |path|
      body = File.read(path)
      # **Every** guard line, not the first. A law may be held by more than one cop —
      # `one-operation-one-class` is held by two, because a module cannot be judged by the
      # cop that walks classes — and reading only the first made the second cop an orphan
      # that `test_every_cop_is_named_by_a_law` then reported as having no law at all.
      guard = body.scan(GUARD_LINE).flatten.join("\n")

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
